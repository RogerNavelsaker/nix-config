package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

var (
	configPath         string
	baoPath            string
	secretMappingsJSON string
	secretMappingsPath string
	touchPath          string
	baoAddress         string
	serverCaPath       string
	clientCertPath     string
	clientKeyPath      string
	startupTimeout     = 60 * time.Second
	startupGrace       = time.Second
)

type secretMapping struct {
	Path  string "json:\"path\""
	Field string "json:\"field\""
}

type selectedSecret struct {
	EnvName string
	Path    string
	Field   string
}

type renderFileSpec struct {
	Name     string
	Selector string
}

type renderSecret struct {
	Name   string
	Secret selectedSecret
}

func usage() string {
	return "Usage: graft [--env PROFILE.VARIABLE]... run -- <command> [args...]"
}

func renderUsage() string {
	return "Usage: graft render --service NAME --file CREDENTIAL=PROFILE.VARIABLE [--file CREDENTIAL=VARIABLE ...]"
}

func validServiceName(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for i, r := range value {
		valid := r == '_' || r == '-' || r == '.' || r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || i > 0 && r >= '0' && r <= '9'
		if !valid || i == 0 && (r == '.' || r == '-' || r == '_') {
			return false
		}
	}
	return value != "." && value != ".."
}

func validCredentialName(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for i, r := range value {
		valid := r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || i > 0 && strings.ContainsRune("_.-", r)
		if !valid {
			return false
		}
	}
	return true
}

func parseRenderArgs(args []string) (string, []renderFileSpec, bool, error) {
	if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
		return "", nil, true, nil
	}
	var service string
	files := []renderFileSpec{}
	for i := 0; i < len(args); {
		switch args[i] {
		case "--service":
			if service != "" || i+1 >= len(args) || !validServiceName(args[i+1]) {
				return "", nil, false, errors.New("render requires one valid --service name")
			}
			service = args[i+1]
			i += 2
		case "--file":
			if i+1 >= len(args) {
				return "", nil, false, errors.New("--file requires CREDENTIAL=SELECTOR")
			}
			name, selector, found := strings.Cut(args[i+1], "=")
			if !found || !validCredentialName(name) || selector == "" {
				return "", nil, false, errors.New("--file requires a safe CREDENTIAL=SELECTOR mapping")
			}
			files = append(files, renderFileSpec{Name: name, Selector: selector})
			i += 2
		default:
			return "", nil, false, fmt.Errorf("unexpected render argument %q", args[i])
		}
	}
	if service == "" || len(files) == 0 {
		return "", nil, false, errors.New("render requires --service and at least one --file")
	}
	return service, files, false, nil
}

func parseRunArgs(args []string) ([]string, []string, bool, error) {
	if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
		return nil, nil, true, nil
	}
	selectors := []string{}
	i := 0
	for i < len(args) && args[i] != "run" {
		if args[i] != "--env" || i+1 >= len(args) || args[i+1] == "" {
			return nil, nil, false, errors.New("expected optional --env selectors followed by run -- <command>")
		}
		selectors = append(selectors, args[i+1])
		i += 2
	}
	if i+2 >= len(args) || args[i] != "run" || args[i+1] != "--" || args[i+2] == "" {
		return nil, nil, false, errors.New("expected: [--env PROFILE.VARIABLE]... run -- <command> [args...]")
	}
	return selectors, args[i+2:], false, nil
}

func validEnvName(value string) bool {
	if value == "" {
		return false
	}
	for i, r := range value {
		valid := r == '_' || r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || i > 0 && r >= '0' && r <= '9'
		if !valid {
			return false
		}
	}
	return true
}

func validProfileName(value string) bool {
	if value == "" {
		return false
	}
	for _, r := range value {
		if !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || strings.ContainsRune("_-", r)) {
			return false
		}
	}
	return true
}

func selectorEnvName(selector string) (string, bool, error) {
	parts := strings.Split(selector, ".")
	switch len(parts) {
	case 1:
		if !validEnvName(parts[0]) {
			return "", false, fmt.Errorf("invalid environment variable selector %q", selector)
		}
		return parts[0], false, nil
	case 2:
		if !validProfileName(parts[0]) || !validEnvName(parts[1]) {
			return "", false, fmt.Errorf("invalid profile-qualified selector %q", selector)
		}
		return parts[1], true, nil
	default:
		return "", false, fmt.Errorf("selector %q must contain at most one profile separator", selector)
	}
}

func safeSecretPath(value string) bool {
	if value == "" || strings.HasPrefix(value, "/") || strings.Contains(value, "//") {
		return false
	}
	for _, part := range strings.Split(value, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
		for _, r := range part {
			if !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || strings.ContainsRune("._-", r)) {
				return false
			}
		}
	}
	return true
}

func parseSecretMappings(data string) (map[string]secretMapping, error) {
	mappings := map[string]secretMapping{}
	if data == "" {
		return mappings, nil
	}
	if err := json.Unmarshal([]byte(data), &mappings); err != nil {
		return nil, fmt.Errorf("decode configured secret mappings: %w", err)
	}
	for selector, mapping := range mappings {
		if _, _, err := selectorEnvName(selector); err != nil {
			return nil, fmt.Errorf("invalid configured selector %q", selector)
		}
		if !safeSecretPath(mapping.Path) || !validEnvName(mapping.Field) {
			return nil, fmt.Errorf("invalid configured mapping for %q", selector)
		}
	}
	return mappings, nil
}

func selectSecrets(selectors []string, mappings map[string]secretMapping) ([]selectedSecret, error) {
	profiledNames := map[string]struct{}{}
	for selector := range mappings {
		envName, profiled, err := selectorEnvName(selector)
		if err != nil {
			return nil, fmt.Errorf("invalid configured selector %q", selector)
		}
		if profiled {
			profiledNames[envName] = struct{}{}
		}
	}
	selected := make([]selectedSecret, 0, len(selectors))
	seenSelectors := map[string]struct{}{}
	seenNames := map[string]struct{}{}
	for _, selector := range selectors {
		envName, profiled, err := selectorEnvName(selector)
		if err != nil {
			return nil, err
		}
		if !profiled {
			if _, exists := profiledNames[envName]; exists {
				return nil, fmt.Errorf("environment variable %q requires an explicit profile", envName)
			}
		}
		mapping, exists := mappings[selector]
		if !exists {
			return nil, fmt.Errorf("unknown or unauthorized environment selector %q", selector)
		}
		if _, exists := seenSelectors[selector]; exists {
			return nil, fmt.Errorf("duplicate environment selector %q", selector)
		}
		if _, exists := seenNames[envName]; exists {
			return nil, fmt.Errorf("multiple selectors target environment variable %q", envName)
		}
		seenSelectors[selector] = struct{}{}
		seenNames[envName] = struct{}{}
		selected = append(selected, selectedSecret{EnvName: envName, Path: mapping.Path, Field: mapping.Field})
	}
	return selected, nil
}

func selectRenderSecrets(specs []renderFileSpec, mappings map[string]secretMapping) ([]renderSecret, error) {
	selectors := make([]string, len(specs))
	seenNames := map[string]struct{}{}
	for i, spec := range specs {
		if !validCredentialName(spec.Name) {
			return nil, fmt.Errorf("invalid credential name %q", spec.Name)
		}
		if _, exists := seenNames[spec.Name]; exists {
			return nil, fmt.Errorf("duplicate credential name %q", spec.Name)
		}
		seenNames[spec.Name] = struct{}{}
		selectors[i] = spec.Selector
	}
	secrets, err := selectSecrets(selectors, mappings)
	if err != nil {
		return nil, err
	}
	selected := make([]renderSecret, len(specs))
	for i, spec := range specs {
		selected[i] = renderSecret{Name: spec.Name, Secret: secrets[i]}
	}
	return selected, nil
}

func withTokenSink(base, tokenPath string) (string, error) {
	if tokenPath == "" {
		return base, nil
	}
	if !filepath.IsAbs(tokenPath) || strings.Count(base, "# GRAFT_TOKEN_SINK") != 1 {
		return "", errors.New("Agent config must contain one token-sink marker and use a private absolute token path")
	}
	path, err := json.Marshal(tokenPath)
	if err != nil {
		return "", err
	}
	sink := "sink {\n  type = \"file\"\n  config = {\n    path = " + string(path) + "\n    mode = 384\n  }\n}"
	return strings.Replace(base, "# GRAFT_TOKEN_SINK", sink, 1), nil
}

func buildConfig(base string, secrets []selectedSecret, command []string, execScript, readyMarker string) (string, error) {
	return buildConfigWithTokenSink(base, secrets, command, execScript, readyMarker, "")
}

func buildConfigWithTokenSink(base string, secrets []selectedSecret, command []string, execScript, readyMarker, tokenPath string) (string, error) {
	var err error
	base, err = withTokenSink(base, tokenPath)
	if err != nil {
		return "", err
	}
	wrappedCommand := append([]string{"/bin/sh", execScript, readyMarker}, command...)
	encoded, err := json.Marshal(wrappedCommand)
	if err != nil {
		return "", err
	}
	var templates strings.Builder
	if len(secrets) > 0 {
		templates.WriteString("template_config {\n  static_secret_render_interval = \"5m\"\n  exit_on_retry_failure = true\n}\n\n")
		for _, secret := range secrets {
			name, err := json.Marshal(secret.EnvName)
			if err != nil {
				return "", err
			}
			path, err := json.Marshal(secret.Path)
			if err != nil {
				return "", err
			}
			contents := "{{ with secret " + string(path) + " }}{{ .Data.data." + secret.Field + " }}{{ end }}"
			encodedContents, err := json.Marshal(contents)
			if err != nil {
				return "", err
			}
			fmt.Fprintf(&templates, "env_template %s {\n  contents = %s\n  error_on_missing_key = true\n}\n\n", name, encodedContents)
		}
	}
	return strings.TrimRight(base, "\n") + "\n\n" + templates.String() + "exec {\n" +
		"  command = " + string(encoded) + "\n" +
		"  restart_on_secret_changes = \"never\"\n" +
		"  restart_stop_signal = \"SIGTERM\"\n}\n", nil
}

func buildRenderConfig(base string, files []renderSecret, stageDir, touchPath string) (string, []string, error) {
	return buildRenderConfigWithTokenSink(base, files, stageDir, touchPath, "")
}

func buildRenderConfigWithTokenSink(base string, files []renderSecret, stageDir, touchPath, tokenPath string) (string, []string, error) {
	var err error
	base, err = withTokenSink(base, tokenPath)
	if err != nil {
		return "", nil, err
	}
	if len(files) == 0 || !filepath.IsAbs(stageDir) || !filepath.IsAbs(touchPath) {
		return "", nil, errors.New("render config requires files and absolute runtime paths")
	}
	markerDir := filepath.Join(stageDir, "ready")
	markers := make([]string, len(files))
	var templates strings.Builder
	templates.WriteString("template_config {\n  exit_on_retry_failure = true\n}\n\n")
	for i, file := range files {
		path, err := json.Marshal(file.Secret.Path)
		if err != nil {
			return "", nil, err
		}
		destination, err := json.Marshal(filepath.Join(stageDir, file.Name))
		if err != nil {
			return "", nil, err
		}
		markers[i] = filepath.Join(markerDir, file.Name)
		contents := "{{ with secret " + string(path) + " }}{{ .Data.data." + file.Secret.Field + " }}{{ end }}"
		encodedContents, err := json.Marshal(contents)
		if err != nil {
			return "", nil, err
		}
		command, err := json.Marshal([]string{touchPath, markers[i]})
		if err != nil {
			return "", nil, err
		}
		fmt.Fprintf(&templates, "template {\n  contents = %s\n  destination = %s\n  create_dest_dirs = false\n  perms = \"0400\"\n  backup = false\n  error_on_missing_key = true\n  exec {\n    command = %s\n  }\n}\n\n", encodedContents, destination, command)
	}
	return strings.TrimRight(base, "\n") + "\n\n" + templates.String(), markers, nil
}

func cleanAgentEnvironment(environment []string, secretNames map[string]struct{}) []string {
	cleaned := make([]string, 0, len(environment))
	for _, entry := range environment {
		key, _, _ := strings.Cut(entry, "=")
		if strings.HasPrefix(key, "BAO_") || strings.HasPrefix(key, "VAULT_") || strings.HasPrefix(key, "OPENBAO_") {
			continue
		}
		if _, ok := secretNames[key]; ok {
			continue
		}
		cleaned = append(cleaned, entry)
	}
	return cleaned
}

func configuredSecretNames(mappings map[string]secretMapping) map[string]struct{} {
	names := make(map[string]struct{})
	for selector := range mappings {
		if envName, _, err := selectorEnvName(selector); err == nil {
			names[envName] = struct{}{}
		}
	}
	return names
}

func writeConfigFile(base string, secrets []selectedSecret, command []string, runtimeDir string) (string, string, func(), error) {
	dir, err := os.MkdirTemp(runtimeDir, "graft-")
	if err != nil && runtimeDir != "" {
		dir, err = os.MkdirTemp("", "graft-")
	}
	if err != nil {
		return "", "", nil, err
	}
	cleanup := func() { _ = os.RemoveAll(dir) }
	execScript := filepath.Join(dir, "exec")
	readyMarker := filepath.Join(dir, "ready")
	configFile := filepath.Join(dir, "agent.hcl")
	if err := os.WriteFile(execScript, []byte("#!/bin/sh\numask 077\n: > \"$1\" || exit 125\nshift\nexec \"$@\"\n"), 0o700); err != nil {
		cleanup()
		return "", "", nil, err
	}
	tokenPath := filepath.Join(dir, "token")
	rendered, err := buildConfigWithTokenSink(base, secrets, command, execScript, readyMarker, tokenPath)
	if err != nil {
		cleanup()
		return "", "", nil, err
	}
	if err := os.WriteFile(configFile, []byte(rendered), 0o600); err != nil {
		cleanup()
		return "", "", nil, err
	}
	return configFile, readyMarker, cleanup, nil
}

func readyFileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func stopAgent(cmd *exec.Cmd, done <-chan error) error {
	if cmd.Process == nil {
		return <-done
	}
	_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	timer := time.NewTimer(startupGrace)
	defer timer.Stop()
	select {
	case err := <-done:
		return err
	case <-timer.C:
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		return <-done
	}
}

func waitForAgentStartup(cmd *exec.Cmd, readyMarker string) (error, bool) {
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	timer := time.NewTimer(startupTimeout)
	defer timer.Stop()
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		if readyFileExists(readyMarker) {
			return <-done, false
		}
		select {
		case err := <-done:
			return err, false
		case <-ticker.C:
		case <-timer.C:
			if readyFileExists(readyMarker) {
				return <-done, false
			}
			select {
			case err := <-done:
				return err, false
			default:
			}
			return stopAgent(cmd, done), true
		}
	}
}

func processExitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		if code := exitErr.ExitCode(); code >= 0 {
			return code
		}
		if status, ok := exitErr.Sys().(syscall.WaitStatus); ok && status.Signaled() {
			return 128 + int(status.Signal())
		}
	}
	return 1
}

func runWithoutSecrets(command, environment []string) int {
	cmd := exec.Command(command[0], command[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = environment
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "starting command:", err)
		return 1
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	for {
		select {
		case err := <-done:
			signal.Stop(signals)
			return processExitCode(err)
		case sig := <-signals:
			_ = syscall.Kill(-cmd.Process.Pid, sig.(syscall.Signal))
		}
	}
}

func privateDirectory(path string, uid uint32) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm()&0o077 != 0 {
		return fmt.Errorf("runtime directory is not private: %s", path)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uid {
		return fmt.Errorf("runtime directory has unexpected owner: %s", path)
	}
	return nil
}

func credentialRuntimeDirectory(service string) (string, error) {
	if !validServiceName(service) {
		return "", errors.New("invalid service name")
	}
	uid := uint32(os.Geteuid())
	var root string
	if uid == 0 {
		root = "/run"
		info, err := os.Lstat(root)
		if err != nil {
			return "", err
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || !ok || stat.Uid != 0 || info.Mode().Perm()&0o022 != 0 {
			return "", errors.New("unsafe system runtime directory")
		}
	} else {
		root = filepath.Join("/run/user", fmt.Sprint(uid))
		if os.Getenv("XDG_RUNTIME_DIR") != root {
			return "", errors.New("XDG_RUNTIME_DIR must be the current user's systemd runtime directory")
		}
		if err := privateDirectory(root, uid); err != nil {
			return "", fmt.Errorf("unsafe user runtime directory: %w", err)
		}
	}
	dir := filepath.Join(root, "graft-"+service)
	if err := privateDirectory(dir, uid); err != nil {
		return "", fmt.Errorf("unsafe Graft runtime directory: %w", err)
	}
	return dir, nil
}

func clearCredentialFiles(dir string, files []renderSecret) error {
	for _, file := range files {
		if !validCredentialName(file.Name) {
			return errors.New("invalid credential name")
		}
		path := filepath.Join(dir, file.Name)
		info, err := os.Lstat(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return err
		}
		if info.IsDir() {
			return fmt.Errorf("credential destination is a directory: %s", file.Name)
		}
		if err := os.Remove(path); err != nil {
			return err
		}
	}
	return nil
}

func publishRenderedFiles(dir, stageDir string, files []renderSecret) error {
	if filepath.Dir(stageDir) != dir {
		return errors.New("render staging directory must be inside the credential directory")
	}
	uid := uint32(os.Geteuid())
	for _, file := range files {
		if !validCredentialName(file.Name) {
			return errors.New("invalid credential name")
		}
		info, err := os.Lstat(filepath.Join(stageDir, file.Name))
		if err != nil {
			return err
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || !ok || stat.Uid != uid {
			return fmt.Errorf("rendered credential is not a regular owned file: %s", file.Name)
		}
		if err := os.Chmod(filepath.Join(stageDir, file.Name), 0o400); err != nil {
			return err
		}
		destination := filepath.Join(dir, file.Name)
		if existing, err := os.Lstat(destination); err == nil && existing.IsDir() {
			return fmt.Errorf("credential destination is a directory: %s", file.Name)
		} else if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	for _, file := range files {
		if err := os.Rename(filepath.Join(stageDir, file.Name), filepath.Join(dir, file.Name)); err != nil {
			_ = clearCredentialFiles(dir, files)
			return err
		}
	}
	return nil
}

func allFilesExist(paths []string) bool {
	for _, path := range paths {
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() {
			return false
		}
	}
	return true
}

func gracefulAgentStop(err error) bool {
	if err == nil {
		return true
	}
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		return false
	}
	status, ok := exitErr.Sys().(syscall.WaitStatus)
	return ok && status.Signaled() && status.Signal() == syscall.SIGTERM
}

func waitForRenderAgent(cmd *exec.Cmd, markers []string) (bool, bool, syscall.Signal, error) {
	if err := cmd.Start(); err != nil {
		return false, false, 0, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(signals)
	timer := time.NewTimer(startupTimeout)
	defer timer.Stop()
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case err := <-done:
			return false, false, 0, err
		default:
		}
		if allFilesExist(markers) {
			err := stopAgent(cmd, done)
			if !gracefulAgentStop(err) {
				return false, false, 0, errors.New("OpenBao Agent did not stop gracefully")
			}
			return true, false, 0, nil
		}
		select {
		case err := <-done:
			return false, false, 0, err
		case sig := <-signals:
			_ = stopAgent(cmd, done)
			return false, false, sig.(syscall.Signal), nil
		case <-timer.C:
			_ = stopAgent(cmd, done)
			return false, true, 0, nil
		case <-ticker.C:
		}
	}
}

func revokeAgentToken(tokenPath string) (bool, error) {
	info, err := os.Lstat(tokenPath)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0o600 || !ok || stat.Uid != uint32(os.Geteuid()) {
		return false, errors.New("Agent token sink is not a private owned file")
	}
	data, err := os.ReadFile(tokenPath)
	if err != nil {
		return false, err
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return false, errors.New("Agent token sink is empty")
	}
	if baoAddress == "" || serverCaPath == "" || clientCertPath == "" || clientKeyPath == "" {
		return true, errors.New("Graft is missing OpenBao CLI connection settings")
	}
	environment := cleanAgentEnvironment(os.Environ(), nil)
	environment = append(environment,
		"BAO_ADDR="+baoAddress,
		"BAO_CACERT="+serverCaPath,
		"BAO_CLIENT_CERT="+clientCertPath,
		"BAO_CLIENT_KEY="+clientKeyPath,
		"BAO_TOKEN="+token,
	)
	cmd := exec.Command(baoPath, "token", "revoke", "-self")
	cmd.Env = environment
	cmd.Stdin, cmd.Stdout, cmd.Stderr = nil, io.Discard, io.Discard
	if err := cmd.Run(); err != nil {
		return true, errors.New("OpenBao token revocation failed")
	}
	return true, nil
}

func runRender(service string, files []renderSecret, mappings map[string]secretMapping) int {
	if configPath == "" || baoPath == "" || touchPath == "" {
		fmt.Fprintln(os.Stderr, "graft is missing its Nix-configured paths")
		return 2
	}
	base, err := os.ReadFile(configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "reading OpenBao Agent config:", err)
		return 1
	}
	dir, err := credentialRuntimeDirectory(service)
	if err != nil {
		fmt.Fprintln(os.Stderr, "validating Graft runtime directory:", err)
		return 1
	}
	if err := clearCredentialFiles(dir, files); err != nil {
		fmt.Fprintln(os.Stderr, "clearing prior credentials:", err)
		return 1
	}
	stageDir, err := os.MkdirTemp(dir, ".graft-render-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "creating private render staging directory:", err)
		return 1
	}
	defer os.RemoveAll(stageDir)
	markerDir := filepath.Join(stageDir, "ready")
	if err := os.Mkdir(markerDir, 0o700); err != nil {
		fmt.Fprintln(os.Stderr, "creating private render marker directory:", err)
		return 1
	}
	tokenPath := filepath.Join(stageDir, "token")
	renderedConfig, markers, err := buildRenderConfigWithTokenSink(string(base), files, stageDir, touchPath, tokenPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "building OpenBao Agent render config:", err)
		return 1
	}
	configFile := filepath.Join(stageDir, "agent.hcl")
	if err := os.WriteFile(configFile, []byte(renderedConfig), 0o600); err != nil {
		fmt.Fprintln(os.Stderr, "writing OpenBao Agent render config:", err)
		return 1
	}
	cmd := exec.Command(baoPath, "agent", "-config="+configFile)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = cleanAgentEnvironment(os.Environ(), configuredSecretNames(mappings))
	ready, timedOut, interrupted, agentErr := waitForRenderAgent(cmd, markers)
	tokenFound, revokeErr := revokeAgentToken(tokenPath)
	if interrupted != 0 {
		if revokeErr != nil {
			fmt.Fprintln(os.Stderr, "warning: OpenBao token could not be revoked before Graft stopped")
		}
		return 128 + int(interrupted)
	}
	if timedOut {
		if revokeErr != nil {
			fmt.Fprintln(os.Stderr, "warning: OpenBao token could not be revoked after render timeout")
		}
		fmt.Fprintf(os.Stderr, "OpenBao Agent did not render credentials within %s\n", startupTimeout)
		return 124
	}
	if agentErr != nil || !ready {
		if revokeErr != nil {
			fmt.Fprintln(os.Stderr, "warning: OpenBao token could not be revoked after render failure")
		}
		fmt.Fprintln(os.Stderr, "OpenBao Agent exited before rendering configured credentials")
		return 1
	}
	if revokeErr != nil || !tokenFound {
		fmt.Fprintln(os.Stderr, "could not revoke OpenBao token; credentials were not published")
		return 1
	}
	if err := publishRenderedFiles(dir, stageDir, files); err != nil {
		fmt.Fprintln(os.Stderr, "publishing rendered credentials:", err)
		return 1
	}
	return 0
}

func run(args []string) int {
	if len(args) > 0 && args[0] == "render" {
		service, specs, showHelp, err := parseRenderArgs(args[1:])
		if showHelp {
			fmt.Println(renderUsage())
			return 0
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, renderUsage())
			return 2
		}
		mappingData := secretMappingsJSON
		if secretMappingsPath != "" {
			data, err := os.ReadFile(secretMappingsPath)
			if err != nil {
				fmt.Fprintln(os.Stderr, "reading configured secret mappings:", err)
				return 1
			}
			mappingData = string(data)
		}
		mappings, err := parseSecretMappings(mappingData)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
		files, err := selectRenderSecrets(specs, mappings)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
		return runRender(service, files, mappings)
	}
	selectors, command, showHelp, err := parseRunArgs(args)
	if showHelp {
		fmt.Println(usage())
		return 0
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, usage())
		return 2
	}
	mappingData := secretMappingsJSON
	if secretMappingsPath != "" {
		data, err := os.ReadFile(secretMappingsPath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "reading configured secret mappings:", err)
			return 1
		}
		mappingData = string(data)
	}
	mappings, err := parseSecretMappings(mappingData)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	secrets, err := selectSecrets(selectors, mappings)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	cleanedEnvironment := cleanAgentEnvironment(os.Environ(), configuredSecretNames(mappings))
	if len(secrets) == 0 {
		return runWithoutSecrets(command, cleanedEnvironment)
	}
	if configPath == "" || baoPath == "" {
		fmt.Fprintln(os.Stderr, "graft is missing its Nix-configured paths")
		return 2
	}
	base, err := os.ReadFile(configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "reading OpenBao Agent config:", err)
		return 1
	}
	temporaryConfig, readyMarker, cleanup, err := writeConfigFile(string(base), secrets, command, os.Getenv("XDG_RUNTIME_DIR"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "creating temporary OpenBao Agent config:", err)
		return 1
	}
	defer cleanup()

	cmd := exec.Command(baoPath, "agent", "-config="+temporaryConfig)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = cleanedEnvironment
	signals := make(chan os.Signal, 1)
	forwarderDone := make(chan struct{})
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	if err := cmd.Start(); err != nil {
		signal.Stop(signals)
		fmt.Fprintln(os.Stderr, "starting OpenBao Agent:", err)
		return 1
	}
	go func() {
		defer close(forwarderDone)
		for sig := range signals {
			if cmd.Process != nil {
				_ = cmd.Process.Signal(sig)
			}
		}
	}()
	err, timedOut := waitForAgentStartup(cmd, readyMarker)
	if found, revokeErr := revokeAgentToken(filepath.Join(filepath.Dir(temporaryConfig), "token")); revokeErr != nil || err == nil && !found {
		fmt.Fprintln(os.Stderr, "warning: OpenBao token could not be revoked; it will expire according to server policy")
	}
	signal.Stop(signals)
	close(signals)
	<-forwarderDone
	if timedOut {
		fmt.Fprintf(os.Stderr, "OpenBao Agent did not start the command within %s\n", startupTimeout)
		return 124
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "OpenBao Agent exited:", err)
	}
	return processExitCode(err)
}

func main() {
	os.Exit(run(os.Args[1:]))
}

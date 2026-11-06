package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func setupFakeAgent(t *testing.T, script string) {
	t.Helper()
	oldConfigPath, oldBaoPath, oldMappings := configPath, baoPath, secretMappingsJSON
	dir := t.TempDir()
	configPath = filepath.Join(dir, "agent.hcl")
	baoPath = filepath.Join(dir, "fake-bao")
	secretMappingsJSON = "{\"TOKEN\":{\"path\":\"kv/data/test\",\"field\":\"token\"}}"
	if err := os.WriteFile(configPath, []byte("vault {}\nauto_auth {\n  # GRAFT_TOKEN_SINK\n}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(baoPath, []byte("#!/bin/sh\n"+script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		configPath, baoPath, secretMappingsJSON = oldConfigPath, oldBaoPath, oldMappings
	})
}

func TestRunBoundsAgentStartup(t *testing.T) {
	oldTimeout, oldGrace := startupTimeout, startupGrace
	startupTimeout, startupGrace = 50*time.Millisecond, 50*time.Millisecond
	t.Cleanup(func() { startupTimeout, startupGrace = oldTimeout, oldGrace })

	pidFile := filepath.Join(t.TempDir(), "agent.pid")
	t.Setenv("GRAFT_TEST_AGENT_PID_FILE", pidFile)
	setupFakeAgent(t, `printf '%s\n' "$$" > "$GRAFT_TEST_AGENT_PID_FILE"
exec sleep 30
`)

	done := make(chan int, 1)
	go func() { done <- run([]string{"--env", "TOKEN", "run", "--", "unused-command"}) }()
	select {
	case got := <-done:
		if got != 124 {
			t.Fatalf("run() = %d, want startup-timeout code 124", got)
		}
		data, err := os.ReadFile(pidFile)
		if err != nil {
			t.Fatal(err)
		}
		pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err != nil {
			t.Fatal(err)
		}
		if err := syscall.Kill(pid, 0); err == nil {
			t.Fatalf("timed-out Agent process %d is still running", pid)
		}
	case <-time.After(500 * time.Millisecond):
		if data, err := os.ReadFile(pidFile); err == nil {
			if pid, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
				_ = syscall.Kill(pid, syscall.SIGKILL)
			}
		}
		<-done
		t.Fatal("run() did not stop an Agent that never started its child")
	}
}

func TestRunStopsStartupTimerAfterChildLaunch(t *testing.T) {
	oldTimeout, oldGrace := startupTimeout, startupGrace
	startupTimeout, startupGrace = 500*time.Millisecond, 50*time.Millisecond
	t.Cleanup(func() { startupTimeout, startupGrace = oldTimeout, oldGrace })

	pidFile := filepath.Join(t.TempDir(), "agent.pid")
	configFile := filepath.Join(t.TempDir(), "agent-config-path")
	t.Setenv("GRAFT_TEST_AGENT_PID_FILE", pidFile)
	t.Setenv("GRAFT_TEST_AGENT_CONFIG_FILE", configFile)
	setupFakeAgent(t, `printf '%s\n' "$$" > "$GRAFT_TEST_AGENT_PID_FILE"
printf '%s\n' "$2" > "$GRAFT_TEST_AGENT_CONFIG_FILE"
exec sleep 30
`)

	done := make(chan int, 1)
	go func() { done <- run([]string{"--env", "TOKEN", "run", "--", "unused-command"}) }()
	deadline := time.Now().Add(2 * time.Second)
	var configArg string
	for time.Now().Before(deadline) {
		if data, err := os.ReadFile(configFile); err == nil {
			configArg = strings.TrimSpace(string(data))
			break
		}
		select {
		case got := <-done:
			t.Fatalf("run() exited before the fake Agent was ready: %d", got)
		default:
		}
		time.Sleep(5 * time.Millisecond)
	}
	if !strings.HasPrefix(configArg, "-config=") {
		t.Fatal("fake Agent did not capture its config path")
	}
	config, err := os.ReadFile(strings.TrimPrefix(configArg, "-config="))
	if err != nil {
		t.Fatal(err)
	}
	var agentCommand []string
	for _, line := range strings.Split(string(config), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "command = ") {
			if err := json.Unmarshal([]byte(strings.TrimPrefix(strings.TrimSpace(line), "command = ")), &agentCommand); err != nil {
				t.Fatal(err)
			}
			break
		}
	}
	if len(agentCommand) < 4 {
		t.Fatalf("generated Agent command lacks the readiness wrapper: %#v", agentCommand)
	}
	if err := os.WriteFile(agentCommand[2], []byte("ready"), 0o600); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-done:
		t.Fatalf("run() exited after readiness with code %d", got)
	case <-time.After(650 * time.Millisecond):
	}

	data, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Kill(pid, syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-done:
		if got != 128+int(syscall.SIGTERM) {
			t.Fatalf("run() after Agent exit = %d, want %d", got, 128+int(syscall.SIGTERM))
		}
	case <-time.After(2 * time.Second):
		_ = syscall.Kill(pid, syscall.SIGKILL)
		<-done
		t.Fatal("run() did not return after the Agent exited")
	}
}

func TestRunPropagatesAgentExitCode(t *testing.T) {
	setupFakeAgent(t, "exit 37\n")
	if got := run([]string{"--env", "TOKEN", "run", "--", "unused-command"}); got != 37 {
		t.Fatalf("run() = %d, want agent exit code 37", got)
	}
}

func TestRunForwardsSignalToAgent(t *testing.T) {
	ready := filepath.Join(t.TempDir(), "ready")
	t.Setenv("GRAFT_READY_MARKER", ready)
	setupFakeAgent(t, `printf '%s\n' "$$" > "$GRAFT_READY_MARKER"
while :; do :; done
`)
	done := make(chan int, 1)
	go func() { done <- run([]string{"--env", "TOKEN", "run", "--", "unused-command"}) }()

	deadline := time.Now().Add(2 * time.Second)
	var pid int
	for time.Now().Before(deadline) {
		if data, err := os.ReadFile(ready); err == nil {
			pid, err = strconv.Atoi(strings.TrimSpace(string(data)))
			if err != nil {
				t.Fatal(err)
			}
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if pid == 0 {
		t.Fatal("fake agent did not start")
	}
	if err := syscall.Kill(os.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-done:
		if got != 128+int(syscall.SIGTERM) {
			t.Fatalf("run() after SIGTERM = %d, want %d", got, 128+int(syscall.SIGTERM))
		}
	case <-time.After(2 * time.Second):
		_ = syscall.Kill(pid, syscall.SIGKILL)
		<-done
		t.Fatal("run() did not forward SIGTERM to the agent")
	}
}

func TestBuildConfigPreservesCommandArgumentsAndSelectedTemplate(t *testing.T) {
	command := []string{"/usr/bin/tool", "--name", "value\"quoted", "line\nbreak"}
	execScript, marker := "/tmp/graft-exec", "/tmp/graft-ready"
	secrets := []selectedSecret{{EnvName: "API_URL", Path: "kv/data/app/production", Field: "url"}}
	rendered, err := buildConfig("vault {}", secrets, command, execScript, marker)
	if err != nil {
		t.Fatal(err)
	}
	wrappedCommand := append([]string{"/bin/sh", execScript, marker}, command...)
	encoded, err := json.Marshal(wrappedCommand)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(rendered, "command = "+string(encoded)) {
		t.Fatalf("generated command does not preserve argv safely:\n%s", rendered)
	}
	if !strings.Contains(rendered, "env_template \"API_URL\"") || !strings.Contains(rendered, "kv/data/app/production") {
		t.Fatalf("generated config omitted selected secret template: %s", rendered)
	}
	if !strings.Contains(rendered, "restart_on_secret_changes = \"never\"") {
		t.Fatalf("generated config must not restart a long-running child: %s", rendered)
	}
}

func TestParseRunArgsRequiresExplicitSelectorsBeforeRun(t *testing.T) {
	selectors, command, help, err := parseRunArgs([]string{"--env", "production.API_URL", "--env", "API_KEY", "run", "--", "env", "APP=1"})
	if err != nil || help || !reflect.DeepEqual(selectors, []string{"production.API_URL", "API_KEY"}) || !reflect.DeepEqual(command, []string{"env", "APP=1"}) {
		t.Fatalf("parseRunArgs() = (%#v, %#v, %v, %v)", selectors, command, help, err)
	}
	selectors, command, help, err = parseRunArgs([]string{"run", "--", "cmd"})
	if err != nil || help || len(selectors) != 0 || !reflect.DeepEqual(command, []string{"cmd"}) {
		t.Fatalf("omitted selector parse = (%#v, %#v, %v, %v)", selectors, command, help, err)
	}
	if _, _, help, err = parseRunArgs([]string{"--help"}); err != nil || !help {
		t.Fatalf("help parse = (help %v, err %v)", help, err)
	}
	for _, args := range [][]string{{}, {"run", "cmd"}, {"run", "--"}, {"bad", "--", "cmd"}, {"--env", "run", "--", "cmd"}} {
		if _, _, help, err := parseRunArgs(args); err == nil || help {
			t.Errorf("parseRunArgs(%q) should reject invalid syntax", args)
		}
	}
}

func TestSelectSecretsRequiresExactAuthorizedMappings(t *testing.T) {
	mappings := map[string]secretMapping{
		"production.API_URL":  {Path: "kv/data/app/production", Field: "url"},
		"development.API_URL": {Path: "kv/data/app/development", Field: "url"},
		"API_KEY":             {Path: "kv/data/app/shared", Field: "key"},
	}
	got, err := selectSecrets([]string{"production.API_URL", "API_KEY"}, mappings)
	want := []selectedSecret{{EnvName: "API_URL", Path: "kv/data/app/production", Field: "url"}, {EnvName: "API_KEY", Path: "kv/data/app/shared", Field: "key"}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("selectSecrets() = (%#v, %v), want (%#v, nil)", got, err, want)
	}
	if got, err := selectSecrets(nil, mappings); err != nil || len(got) != 0 {
		t.Fatalf("omitted selection = (%#v, %v), want no secrets", got, err)
	}
	for _, selectors := range [][]string{{"API_URL"}, {"missing.KEY"}, {"bad..NAME"}, {"bad profile.API_URL"}, {"production.API_URL", "production.API_URL"}, {"production.API_URL", "development.API_URL"}} {
		if _, err := selectSecrets(selectors, mappings); err == nil {
			t.Errorf("selectSecrets(%q) should reject invalid/ambiguous selection", selectors)
		}
	}
}

func TestUsageNamesGraft(t *testing.T) {
	if got := usage(); got != "Usage: graft [--env PROFILE.VARIABLE]... run -- <command> [args...]" {
		t.Fatalf("usage() = %q", got)
	}
}

func TestRunWithoutEnvSkipsOpenBaoAndInjectsNothing(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "agent-started")
	t.Setenv("GRAFT_TEST_AGENT_MARKER", marker)
	setupFakeAgent(t, "printf called > \"$GRAFT_TEST_AGENT_MARKER\"\nexit 0\n")
	if got := run([]string{"run", "--", "/bin/sh", "-c", "exit 23"}); got != 23 {
		t.Fatalf("run without selectors = %d, want child exit code 23", got)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("OpenBao Agent ran without an explicit selector: %v", err)
	}
}

func TestCleanAgentEnvironmentDropsOnlyCredentialOverrides(t *testing.T) {
	input := []string{
		"HOME=/home/test",
		"PI_CODING_AGENT_DIR=/home/test/.pi/agent",
		"BAO_ADDR=https://unexpected.invalid",
		"BAO_TOKEN=test-token",
		"VAULT_TOKEN=test-token",
		"OPENBAO_CONFIG=/tmp/override",
		"APP_TOKEN=injected",
		"LITELLM_API_KEY=caller-provided",
	}
	want := []string{
		"HOME=/home/test",
		"PI_CODING_AGENT_DIR=/home/test/.pi/agent",
		"LITELLM_API_KEY=caller-provided",
	}
	if got := cleanAgentEnvironment(input, map[string]struct{}{"APP_TOKEN": {}}); !reflect.DeepEqual(got, want) {
		t.Fatalf("cleanAgentEnvironment() = %#v, want %#v", got, want)
	}
}

func TestWriteConfigFileIsPrivateAndRemovable(t *testing.T) {
	runtimeDir := t.TempDir()
	path, marker, cleanup, err := writeConfigFile("vault {}\nauto_auth {\n  # GRAFT_TOKEN_SINK\n}\n", nil, []string{"env"}, runtimeDir)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("temporary config permissions = %04o, want 0600", got)
	}
	dir := filepath.Dir(path)
	if got := filepath.Base(dir); !strings.HasPrefix(got, "graft-") {
		t.Fatalf("temporary directory = %q, want graft prefix", dir)
	}
	if info, err := os.Stat(dir); err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("temporary directory mode = %v, err = %v; want 0700", info, err)
	}
	if info, err := os.Stat(filepath.Join(dir, "exec")); err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("exec wrapper mode = %v, err = %v; want 0700", info, err)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("ready marker already exists before Agent starts: %v", err)
	}
	cleanup()
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("temporary directory still exists after cleanup: %v", err)
	}
}

func TestParseRenderArgs(t *testing.T) {
	service, files, help, err := parseRenderArgs([]string{
		"--service", "web-api",
		"--file", "api-key=production.API_KEY",
		"--file", "ca-cert=CA_CERT",
	})
	if err != nil || help || service != "web-api" {
		t.Fatalf("parseRenderArgs() = %q, %#v, %v, %v", service, files, help, err)
	}
	if got := files; !reflect.DeepEqual(got, []renderFileSpec{
		{Name: "api-key", Selector: "production.API_KEY"},
		{Name: "ca-cert", Selector: "CA_CERT"},
	}) {
		t.Fatalf("file specs = %#v", got)
	}
	if _, _, help, err := parseRenderArgs([]string{"--help"}); err != nil || !help {
		t.Fatalf("help result = %v, %v", help, err)
	}
	for _, args := range [][]string{
		{"--service", "../web", "--file", "key=TOKEN"},
		{"--service", "web", "--file", "../key=TOKEN"},
		{"--service", "web", "--file", "key="},
		{"--service", "web"},
		{"--service", "web", "--service", "api", "--file", "key=TOKEN"},
	} {
		if _, _, _, err := parseRenderArgs(args); err == nil {
			t.Errorf("parseRenderArgs(%q) unexpectedly succeeded", args)
		}
	}
}

func TestSelectRenderSecretsRequiresConfiguredSelectorsAndUniqueNames(t *testing.T) {
	mappings, err := parseSecretMappings("{\"production.API_KEY\":{\"path\":\"kv/data/app\",\"field\":\"api_key\"},\"CA_CERT\":{\"path\":\"kv/data/certs\",\"field\":\"ca\"}}")
	if err != nil {
		t.Fatal(err)
	}
	got, err := selectRenderSecrets([]renderFileSpec{
		{Name: "api-key", Selector: "production.API_KEY"},
		{Name: "ca-cert", Selector: "CA_CERT"},
	}, mappings)
	if err != nil || len(got) != 2 || got[0].Secret.Path != "kv/data/app" || got[1].Name != "ca-cert" {
		t.Fatalf("selected files = %#v, err = %v", got, err)
	}
	for _, specs := range [][]renderFileSpec{
		{{Name: "same", Selector: "production.API_KEY"}, {Name: "same", Selector: "CA_CERT"}},
		{{Name: "unknown", Selector: "missing.TOKEN"}},
		{{Name: "bare", Selector: "API_KEY"}},
	} {
		if _, err := selectRenderSecrets(specs, mappings); err == nil {
			t.Errorf("selectRenderSecrets(%#v) unexpectedly succeeded", specs)
		}
	}
}

func TestBuildRenderConfigContainsOnlySelectedFiles(t *testing.T) {
	files := []renderSecret{{Name: "api-key", Secret: selectedSecret{EnvName: "API_KEY", Path: "kv/data/app", Field: "api_key"}}}
	stage := filepath.Join(t.TempDir(), "stage")
	config, markers, err := buildRenderConfig("vault {}", files, stage, "/nix/store/coreutils/bin/touch")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"kv/data/app", filepath.Join(stage, "api-key"), "perms = ", "0400", "backup = false", "error_on_missing_key = true", "exit_on_retry_failure = true", "coreutils/bin/touch"} {
		if !strings.Contains(config, want) {
			t.Errorf("render config omitted %q: %s", want, config)
		}
	}
	if strings.Contains(config, "unselected-secret") || len(markers) != 1 || markers[0] != filepath.Join(stage, "ready", "api-key") {
		t.Fatalf("unexpected render config or markers: %s %#v", config, markers)
	}
}

func TestPublishRenderedFilesProtectsAndAtomicallyInstallsOutputs(t *testing.T) {
	dir := t.TempDir()
	stage := filepath.Join(dir, ".stage")
	if err := os.Mkdir(stage, 0o700); err != nil {
		t.Fatal(err)
	}
	files := []renderSecret{{Name: "one"}, {Name: "two"}}
	if err := os.WriteFile(filepath.Join(stage, "one"), []byte("fixture-one"), 0o400); err != nil {
		t.Fatal(err)
	}
	if err := publishRenderedFiles(dir, stage, files); err == nil {
		t.Fatal("publishRenderedFiles() succeeded with a missing staged file")
	}
	if _, err := os.Lstat(filepath.Join(dir, "one")); !os.IsNotExist(err) {
		t.Fatalf("partial credential was published: %v", err)
	}
	if err := os.WriteFile(filepath.Join(stage, "two"), []byte("fixture-two"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := publishRenderedFiles(dir, stage, files); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]string{"one": "fixture-one", "two": "fixture-two"} {
		path := filepath.Join(dir, name)
		got, err := os.ReadFile(path)
		if err != nil || string(got) != want {
			t.Errorf("%s = %q, err = %v", name, got, err)
		}
		info, err := os.Stat(path)
		if err != nil || info.Mode().Perm() != 0o400 {
			t.Errorf("%s mode = %v, err = %v; want 0400", name, info, err)
		}
	}
}

func TestPublishRenderedFilesRejectsSymlinkStage(t *testing.T) {
	dir := t.TempDir()
	stage := filepath.Join(dir, ".stage")
	if err := os.Mkdir(stage, 0o700); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "outside")
	if err := os.WriteFile(outside, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(stage, "secret")); err != nil {
		t.Fatal(err)
	}
	if err := publishRenderedFiles(dir, stage, []renderSecret{{Name: "secret"}}); err == nil {
		t.Fatal("publishRenderedFiles() accepted a symlink")
	}
	if _, err := os.Lstat(filepath.Join(dir, "secret")); !os.IsNotExist(err) {
		t.Fatalf("symlink credential was published: %v", err)
	}
}

func TestPrivateDirectoryRejectsPublicAndSymlinkDirectories(t *testing.T) {
	dir := t.TempDir()
	if err := os.Chmod(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	uid := uint32(os.Geteuid())
	if err := privateDirectory(dir, uid); err != nil {
		t.Fatalf("private directory rejected: %v", err)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := privateDirectory(dir, uid); err == nil {
		t.Fatal("privateDirectory() accepted a public directory")
	}
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(dir, link); err != nil {
		t.Fatal(err)
	}
	if err := privateDirectory(link, uid); err == nil {
		t.Fatal("privateDirectory() accepted a symlink")
	}
}

func TestWaitForRenderAgentStopsAfterAllMarkers(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "ready")
	cmd := exec.Command("/bin/sh", "-c", ": > \"$1\"; exec sleep 30", "sh", marker)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	ready, timedOut, interrupted, err := waitForRenderAgent(cmd, []string{marker})
	if err != nil || !ready || timedOut || interrupted != 0 {
		t.Fatalf("waitForRenderAgent() = (%v, %v, %v, %v)", ready, timedOut, interrupted, err)
	}
}

func TestWaitForRenderAgentTimesOutAndStopsChild(t *testing.T) {
	oldTimeout, oldGrace := startupTimeout, startupGrace
	startupTimeout, startupGrace = 50*time.Millisecond, 50*time.Millisecond
	t.Cleanup(func() { startupTimeout, startupGrace = oldTimeout, oldGrace })
	cmd := exec.Command("/bin/sh", "-c", "exec sleep 30")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	ready, timedOut, interrupted, err := waitForRenderAgent(cmd, []string{filepath.Join(t.TempDir(), "missing")})
	if err != nil || ready || !timedOut || interrupted != 0 {
		t.Fatalf("waitForRenderAgent() = (%v, %v, %v, %v)", ready, timedOut, interrupted, err)
	}
}

func TestWithTokenSinkUsesOnlyRuntimePath(t *testing.T) {
	base := "auto_auth {\n  # GRAFT_TOKEN_SINK\n}\n"
	rendered, err := withTokenSink(base, "/run/graft-test/token")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(rendered, "GRAFT_TOKEN_SINK") || !strings.Contains(rendered, "/run/graft-test/token") || !strings.Contains(rendered, "mode = 384") {
		t.Fatalf("token sink config is incomplete: %s", rendered)
	}
	if _, err := withTokenSink("auto_auth {}", "/tmp/token"); err == nil {
		t.Fatal("withTokenSink() accepted a config without its insertion marker")
	}
}

func TestRevokeAgentTokenKeepsTokenOutOfArgumentsAndOutput(t *testing.T) {
	oldBaoPath, oldAddress, oldCA, oldCert, oldKey := baoPath, baoAddress, serverCaPath, clientCertPath, clientKeyPath
	dir := t.TempDir()
	baoPath = filepath.Join(dir, "fake-bao")
	baoAddress, serverCaPath, clientCertPath, clientKeyPath = "https://bao.example.test", "/run/ca.pem", "/run/client.pem", "/run/client-key.pem"
	tokenCapture := filepath.Join(dir, "token-capture")
	argsCapture := filepath.Join(dir, "args-capture")
	t.Setenv("GRAFT_TOKEN_CAPTURE", tokenCapture)
	t.Setenv("GRAFT_ARGS_CAPTURE", argsCapture)
	if err := os.WriteFile(baoPath, []byte("#!/bin/sh\nprintf %s $BAO_TOKEN > $GRAFT_TOKEN_CAPTURE\nprintf '%s\\n' $@ > $GRAFT_ARGS_CAPTURE\nprintf suppressed\nprintf suppressed >&2\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		baoPath, baoAddress, serverCaPath, clientCertPath, clientKeyPath = oldBaoPath, oldAddress, oldCA, oldCert, oldKey
	})
	tokenPath := filepath.Join(dir, "token")
	if err := os.WriteFile(tokenPath, []byte("fixture-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	found, err := revokeAgentToken(tokenPath)
	if err != nil || !found {
		t.Fatalf("revokeAgentToken() = (%v, %v)", found, err)
	}
	capturedToken, err := os.ReadFile(tokenCapture)
	if err != nil || string(capturedToken) != "fixture-token" {
		t.Fatalf("fake revoke did not receive token through environment: %q, %v", capturedToken, err)
	}
	args, err := os.ReadFile(argsCapture)
	if err != nil || string(args) != "token\nrevoke\n-self\n" || strings.Contains(string(args), "fixture-token") {
		t.Fatalf("token appeared in revoke arguments: %q, %v", args, err)
	}
}

func TestRevokeAgentTokenRejectsSymlink(t *testing.T) {
	dir := t.TempDir()
	tokenPath := filepath.Join(dir, "token")
	outside := filepath.Join(dir, "outside")
	if err := os.WriteFile(outside, []byte("fixture-token"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, tokenPath); err != nil {
		t.Fatal(err)
	}
	if _, err := revokeAgentToken(tokenPath); err == nil {
		t.Fatal("revokeAgentToken() accepted a symlink token sink")
	}
}

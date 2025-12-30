# users/rona/aio/lib.nix
#
# Helper functions for goose recipe generation
#
{ lib }:
{
  # Convert parameters to YAML format
  mkGooseRecipe =
    {
      name,
      description,
      prompt,
      parameters ? [ ],
    }:
    let
      paramsYaml =
        if parameters == [ ] then
          ""
        else
          ''
            parameters:
            ${lib.concatMapStringsSep "\n" (
              p:
              "  - key: ${p.key}\n    input_type: ${p.type or "string"}\n    requirement: ${p.requirement or "optional"}"
            ) parameters}
          '';
    in
    ''
      version: "1.0.0"
      title: "${name}"
      description: "${description}"
      prompt: |
        ${lib.concatMapStringsSep "\n  " (x: x) (lib.splitString "\n" prompt)}
      ${paramsYaml}
    '';
}

let Prelude = ../../External/Prelude.dhall

let Cmd = ../../Lib/Cmds.dhall
let S = ../../Lib/SelectFiles.dhall
let D = S.PathPattern

let Pipeline = ../../Pipeline/Dsl.dhall
let PipelineTag = ../../Pipeline/Tag.dhall

let JobSpec = ../../Pipeline/JobSpec.dhall

let Command = ../../Command/Base.dhall
let RunInToolchain = ../../Command/RunInToolchain.dhall
let Docker = ../../Command/Docker/Type.dhall
let Size = ../../Command/Size.dhall
let DebianVersions = ../../Constants/DebianVersions.dhall
let Dockers = ../../Constants/DockerVersions.dhall
let Profiles = ../../Constants/Profiles.dhall


let dependsOn = Dockers.dependsOnKey "TestSuiteArtifact" Dockers.Type.Bullseye Profiles.Type.Standard "test-suite"

in

let buildTestCmd : Size -> Command.Type = \(cmd_target : Size) ->
  let key = "single-node-tests" in
  Command.build
    Command.Config::{
      commands = [
        Cmd.run "buildkite/scripts/single-node-tests.sh && buildkite/scripts/upload-partial-coverage-data.sh ${key}"
      ],
      label = "Test: Single Node",
      key = key,
      target = cmd_target,
      docker = None Docker.Type,
      depends_on = dependsOn 
    }

in

Pipeline.build
  Pipeline.Config::{
    spec = 
      let unitDirtyWhen = [
        S.strictlyStart (S.contains "src/lib"),
        S.strictlyStart (S.contains "src/test"),
        S.strictly (S.contains "Makefile"),
        S.exactly "buildkite/src/Jobs/Test/SingleNodeTest" "dhall",
        S.exactly "buildkite/scripts/single-node-tests" "sh"
      ]

      in

      JobSpec::{
        dirtyWhen = unitDirtyWhen,
        path = "Test",
        name = "SingleNodeTest",
        tags = [ PipelineTag.Type.Long, PipelineTag.Type.Test ]
      },
    steps = [
      buildTestCmd Size.XLarge
    ]
  }
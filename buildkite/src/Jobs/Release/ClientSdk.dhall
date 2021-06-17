let Prelude = ../../External/Prelude.dhall

let S = ../../Lib/SelectFiles.dhall
let Cmd = ../../Lib/Cmds.dhall

let Pipeline = ../../Pipeline/Dsl.dhall
let JobSpec = ../../Pipeline/JobSpec.dhall

let Command = ../../Command/Base.dhall
let OpamInit = ../../Command/OpamInit.dhall
let Docker = ../../Command/Docker/Type.dhall
let Size = ../../Command/Size.dhall

in

Pipeline.build
  Pipeline.Config::{
    spec = 
      JobSpec::{
        dirtyWhen = OpamInit.dirtyWhen # [
          S.strictlyStart (S.contains "buildkite/src/Jobs/Release/ClientSdk"),
          S.strictlyStart (S.contains "frontend/client_sdk"),
          S.strictlyStart (S.contains "src")
        ],
        path = "Release",
        name = "ClientSdk"
      },
    steps = [
      Command.Config::{
        commands = [
          Cmd.run "chmod -R 777 frontend/client_sdk",
          Cmd.runInDocker
            Cmd.Docker::{image = (../../Constants/ContainerImages.dhall).minaToolchain}
            "cd frontend/client_sdk && yarn install"
        ]
        , label = "Install Yarn dependencies"
        , key = "install-yarn-deps"
        , target = Size.Small
        , docker = None Docker.Type
      },
      Command.build
        Command.Config::{
          commands = OpamInit.andThenRunInDocker (["NPM_TOKEN"]) "./buildkite/scripts/client-sdk-tool.sh 'publish --non-interactive'"
          , label = "Publish client SDK to npm"
          , key = "publish-client-sdk"
          , target = Size.Medium
          , docker = None Docker.Type
        }
    ]
  }


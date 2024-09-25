let Cmd = ../../Lib/Cmds.dhall

let S = ../../Lib/SelectFiles.dhall

let B = ../../External/Buildkite.dhall

let B/SoftFail = B.definitions/commandStep/properties/soft_fail/Type

let Pipeline = ../../Pipeline/Dsl.dhall

let PipelineTag = ../../Pipeline/Tag.dhall

let JobSpec = ../../Pipeline/JobSpec.dhall

let Command = ../../Command/Base.dhall

let RunInToolchain = ../../Command/RunInToolchain.dhall

let Docker = ../../Command/Docker/Type.dhall

let Size = ../../Command/Size.dhall

let DebianVersions = ../../Constants/DebianVersions.dhall

let Network = ../../Constants/Network.dhall

let Profiles = ../../Constants/Profiles.dhall

let dependsOn =
      DebianVersions.dependsOn
        DebianVersions.DebVersion.Bullseye
        Network.Type.Devnet
        Profiles.Type.Standard

let buildTestCmd
    : Text -> Size -> List Command.TaggedKey.Type -> B/SoftFail -> Command.Type
    =     \(release_branch : Text)
      ->  \(cmd_target : Size)
      ->  \(dependsOn : List Command.TaggedKey.Type)
      ->  \(soft_fail : B/SoftFail)
      ->  Command.build
            Command.Config::{
            , commands =
                  RunInToolchain.runInToolchain
                    ([] : List Text)
                    "buildkite/scripts/dump-mina-type-shapes.sh"
                # [ Cmd.run
                      "gsutil cp \$(git log -n 1 --format=%h --abbrev=7)-type_shape.txt \$MINA_TYPE_SHAPE gs://mina-type-shapes"
                  ]
                # RunInToolchain.runInToolchain
                    ([] : List Text)
                    "buildkite/scripts/version-linter.sh ${release_branch}"
            , label = "Versioned type linter for ${release_branch}"
            , key = "version-linter-${release_branch}"
            , soft_fail = Some soft_fail
            , target = cmd_target
            , docker = None Docker.Type
            , depends_on = dependsOn
            , artifact_paths = [ S.contains "core_dumps/*" ]
            }

in  Pipeline.build
      Pipeline.Config::{
      , spec =
          let lintDirtyWhen =
                [ S.strictlyStart (S.contains "src")
                , S.exactly "buildkite/src/Jobs/Test/VersionLint" "dhall"
                , S.exactly "buildkite/scripts/version-linter" "sh"
                ]

          in  JobSpec::{
              , dirtyWhen = lintDirtyWhen
              , path = "Test"
              , name = "VersionLint"
              , tags =
                [ PipelineTag.Type.Long
                , PipelineTag.Type.Test
                , PipelineTag.Type.Stable
                ]
              }
      , steps =
        [ buildTestCmd
            "compatible"
            Size.Multi
            dependsOn
            (B/SoftFail.Boolean True)
        , buildTestCmd "develop" Size.Multi dependsOn (B/SoftFail.Boolean True)
        , buildTestCmd "master" Size.Multi dependsOn (B/SoftFail.Boolean True)
        ]
      }

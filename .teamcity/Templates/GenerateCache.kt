package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.buildFeatures.buildCache

open class GenerateCache(platformOs: String) : Template() {
    init {
        name = "GenerateCache${platformOs}_Template"

        vcs {
            root(Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        features {
            buildCache {
                id = "Ribasim${platformOs}Cache"
                name = "Ribasim ${platformOs} Cache"
                use = false
                rules = """
                    %teamcity.agent.jvm.user.home%/.julia
                    %teamcity.agent.jvm.user.home%/.pixi
                """.trimIndent()
            }
        }

        val header = generateTestBinariesHeader(platformOs)
        steps {
            script {
                name = "Set up pixi"
                id = "Set_up_pixi"
                workingDir = "ribasim"
                scriptContent =  header +
                """
                pixi --version
                pixi run install-ci
                pixi run instantiate-julia
                """.trimIndent()
            }
        }
    }
}

object GenerateCacheWindows : GenerateCache("Windows")
object GenerateCacheLinux : GenerateCache("Linux")

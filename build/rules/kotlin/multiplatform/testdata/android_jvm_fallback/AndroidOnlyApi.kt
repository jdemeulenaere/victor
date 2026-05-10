package victor.rules.kotlin.multiplatform.testdata

object AndroidOnlyApi {
    fun value(): String = CommonApi.value()
}

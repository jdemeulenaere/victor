package victor.rules.kotlin.multiplatform.testdata

class AndroidConsumesJvmOnly {
    fun value(): String = JvmOnlyApi.value()
}

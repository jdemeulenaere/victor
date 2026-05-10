package victor.rules.kotlin.multiplatform.testdata

class AndroidConsumesAndroidVariant {
    fun value(): String = AndroidOnlyApi.value()
}

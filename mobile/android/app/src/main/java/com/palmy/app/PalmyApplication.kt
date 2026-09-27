package com.palmy.app

import android.app.Application

/** Owns construction only; identities, tokens, and finance stay in the activity ViewModel. */
open class PalmyApplication: Application() {
    open fun createModel() = PalmyModel()
}

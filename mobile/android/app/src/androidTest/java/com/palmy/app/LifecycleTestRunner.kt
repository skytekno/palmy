package com.palmy.app

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner

class LifecycleTestApplication: PalmyApplication() {
    lateinit var modelFactory: () -> PalmyModel
    override fun createModel() = modelFactory()
}

class LifecycleTestRunner: AndroidJUnitRunner() {
    override fun newApplication(loader: ClassLoader, className: String, context: Context): Application =
        super.newApplication(loader, LifecycleTestApplication::class.java.name, context)
}

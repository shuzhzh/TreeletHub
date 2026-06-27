package com.treelet.treelethub

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.treelet.treelethub.locale.HubAndroidUILanguage
import com.treelet.treelethub.ui.TreeletHubApp
import com.treelet.treelethub.ui.TreeletHubViewModel

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        HubAndroidUILanguage.bootstrapIfNeeded(newBase)
        super.attachBaseContext(HubAndroidUILanguage.wrapContext(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val vm: TreeletHubViewModel = viewModel()

            DisposableEffect(vm) {
                val owner = ProcessLifecycleOwner.get().lifecycle
                val obs =
                    LifecycleEventObserver { _, event ->
                        if (event == Lifecycle.Event.ON_START) {
                            vm.client.reconnectFromCacheIfNeededOnForeground()
                            vm.billing.refreshFromStore()
                        }
                    }
                owner.addObserver(obs)
                onDispose { owner.removeObserver(obs) }
            }

            TreeletHubApp(vm = vm)
        }
    }
}

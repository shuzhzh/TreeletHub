package com.treelet.treelethub.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.treelet.treelethub.billing.HubAndroidBillingManager
import com.treelet.treelethub.hub.HubAndroidClient

class TreeletHubViewModel(application: Application) : AndroidViewModel(application) {
    val client = HubAndroidClient(application.applicationContext, viewModelScope)
    val billing = HubAndroidBillingManager(application)

    init {
        client.restorePairingFromDiskOnLaunch()
    }

    override fun onCleared() {
        client.onDestroy()
        billing.destroy()
        super.onCleared()
    }
}

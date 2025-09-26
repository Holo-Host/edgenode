# Holochain Edge Hosting

## Overview

Holochain Edge Hosting provides a straightforward path for Holochain hApp providers to solve some of the core challenges of running p2p applications:

1. Small p2p networks with mostly off-line nodes often need always-on-nodes to hold and relay information.  
2. P2p applications often need to interact with legacy centralized protocols and services, for example they may need to safely manage a boundary to the wider web and provide read-only access to portions of  the contents of the p2p app via http, or they may need to connect to email or sms service providers.  
3. Groups running such p2p apps may not have the technical resources to provision and maintain the hardware and software that overcomes these limitations.

We solve these challenges in a very simple way with two technical components and simple standard:

1. An OCI compliant container configured to run a Holochain conductor which also comes with a few simple command line tools to install and manage Holochain applications (hApps).  
2. An lightweight linux distro image on ISO (created with BuildBox) that is specially configured to easily run such containers.  
3. A simple configuration file standard for specifying a hApp for use by application providers to be used in the containers.

With these tools it becomes very simple for a community based distributed Hosting network to emerge.  Groups that want to run an application and need to solve the challenges described above can simply create a configuration file specifying the application they want to run and send it to a”Edge Hoster” who is running the container.  Of course the terms of that negotiation are completely up to the parties involved, but we also include in the configuration file and in the container image, the information slots and service reporting tools to  account for the services using a Unyt based mutual credit currency.  For more about Unyt please see:  [TODO]

The rest of this documentation provides instructions from two vantage points:  Application Providers and Edge Hosters.  For Application Providers the instructions are simply about how to create the configuration file of the hApp they want to run which they will send to an Edge Hoster.  For Edge Hosters, the instructions include how to set up a hosting node, and how to install and manage applications using configuration files created by Application Providers.

## Application Provider Instructions

Application Providers need simply to create a json configuration file using the following template and then send make it available to the Hoster to install:

Step 1: Create JSON file using this template, modifying the fields appropriately:

{  
  "app": {  
    "name": "example_happ",  
    "version": "0.1.0",  
    "happUrl": "https://github.com/example/v0.1.0/example_happ.happ",  
    "modifiers": {  
      "networkSeed": "", // any string value  
      "properties": {} // any json value  
    },  
    "init_zome_calls": [  
      {  
        fn_name: "some_zome_fn",  
        payload: {}, // any json value  
      }  
    ]  
  },  
  "env": {  
    "holochain": {  
      "version": "",  
      "flags": [""],  
      "bootstrapUrl": "",  
      "signalServerUrl": "",  
    },  
    "gw": {  
      "enable": false,  
      "allowedFns": [""],  
      "dnsProps": [""]  
    }  
  },  
  "economics": {   
      "payorUnytAgentPubKey": "",  
      "agreementHash": "",   
      "payeeUnytAgentPubKey": "",         
 "priceSheetHash": ""    
  }  
}

Some notes on the contents of the fields:

- `networkSeed`: this seed must match the seed used by other participants in the network, otherwise the node will not participate in the application.
- `payorUnytAgentPubKey`: Unyt Agent who will be paying  
- `agreementHash`: the action hash agreement that invoices will get attached to for the work performed.  
- `payeeUnytAgentPubKey`: Optional Unyt Agent who will get paid (will be validated against sys registered agent)  
- `priceSheetHash`: Optional data blob action hash, in case different hosts can have different prices and it's not fixed in the Agreement

Step 2: Send the file to the Hoster or put it someplace on the internet so that it can be downloaded, i.e. a github.gist, etc.

Thats’ it!

## Edge Hoster Instructions

To be an Edge Hosters you simply need to run the OCI container on the platform of your choice.  This can be a virtual machine,  a machine that you already have that runs docker or some other OCI container executable device, or a machine on which you have installed our minimal Linux ISO image.  Here we provide instructions for various of these use-cases:

### I have a HoloPort or spare computer at home I want to use for Edge Hosting

Step 1: Install the ISO on the machine:

1. Download the ISO image here: {TODO}  
2. Install it on a usb stick as a bootable device following these instructions: {Link TODO}  
3. Boot your computer from the ISO   
4. Choose the configuration you want:  
   1. Networking  
   2. Hard-drive  
   3. Container  
5. Install

Step 2: Run the container and verify that Holochain is installed an operational:

1. Container run commands: [TODO]  
2. Holochain verification test commands: [TODO]

Step 2.5 (If you are using Unyt for service logging and accounting)

1. Register the container with Unyt using your payee Unyt Agent Key:  
2. TODO: the registration command:

Step 3: Install a hApp from a configuration file:

1. Use `wget` to get the configuration file on your machine, e.g.:  
   `wget https://gist.github.com/zippy/28a93d63470256bde57738336a476e18`   
2. Verify the configuration file use the `happ_config_file` tool:  
   `$ happ_config_file validate --input example_config.json`  
   This command will confirm that the structure and contents of the config file are valid.  
3. Install the app:  
   `install_app example_config.json`  
4. Verify the installation by looking at the installed apps with:  
   `hc s call -r 4444 list-apps`

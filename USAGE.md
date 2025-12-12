# Edge Node

## Overview

Using Edge Node to run an always-on node for your Holochain application solves one of the core challenges faced by users of p2p applications - staying in sync with the latest changes while peers are constantly going online and offline at different times.

Applications are installed in the Edge Node container via the  'install_happ' tool using a configuration file which can be generated and validated using the 'happ_config_file' tool. The happ config file specifies the application to be installed in the Edge Node container instance. 

The configuration file and the container image, include some experimental support for connection with Unyt (https://unyt.co) based accounting tools for tracking resources used. 

The rest of this usage documentation provides instructions from two vantage points:  Application Managers and Edge Node Operators. Please note it's possible these two can be one in the same.

- For Application Managers, the instructions are simply about how to create the configuration file of the hApp to be run on an Edge Node.
- For Edge Node Operators, the instructions include how to set up a node, and how to install and manage always-on nodes for applications using configuration files.

## Application Manager Instructions

Application managers create a json configuration file with the pertitent hApp details and then make it available to the Edge Node Operator to install:

Step 1: Create JSON file using `happ_config_file create`, modifying the fields of the template created appropriately:

```json
{  
  "app": {  
    "name": "example_happ",  
    "version": "0.1.0",  
    "happUrl": "https://github.com/example/v0.1.0/example_happ.happ", // Can also be a .webhapp URL  
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
```

Some notes on the contents of the fields:

- `networkSeed`: this seed must match the seed used by other participants in the network, otherwise the node will not participate in the application.
- `init_zome_calls`: This array allows you to specify zome calls that should be executed right after the hApp is installed. This is useful for initialization tasks.
  - The `payload` field in a zome call can contain the placeholder `<NODE_NAME>`. This placeholder will be dynamically replaced with the `NODE_NAME` provided during the `install_happ` execution. If no `NODE_NAME` is provided, it defaults to the machine's hostname. This is particularly useful for creating flexible configurations that can be reused across different nodes without modification. For example, you could have a payload like `{"node_name": "<NODE_NAME>"}` and the script will substitute `<NODE_NAME>` with the actual node name.

** Experimental fields for Unyt support: **
- `payorUnytAgentPubKey`: Unyt Agent who should receive resource accounting information
- `agreementHash`: the action hash agreement that associated governing how work performed should be treated.
- `payeeUnytAgentPubKey`: Optional Unyt Agent who will get paid (will be validated against sys registered agent)
- `priceSheetHash`: Optional data blob action hash, in case different nodes can use different prices and it's not fixed in the Agreement

Step 2: Send the file to the Edge Node Operator or put it someplace on the internet so that it can be downloaded, i.e. a github.gist, etc.

That's it!

## Edge Node Operator Instructions

To be an Edge Node Operator, you simply need to pull down and run the Edge Node container on the platform of your choice.  This can be a HoloPort, virtual machine, a machine that you already have that runs docker or some other OCI container executable device, or any other machine on which you have installed our minimal Linux ISO image. The key requirement is that you are running Docker. Here we provide instructions for various of these use-cases:

### I have a HoloPort or spare computer at home I want to use for providing an Edge Node

Step 1: Install the ISO on the machine:

1. Download the ISO image here: https://github.com/Holo-Host/edgenode/releases/tag/v0.0.7ga.5
2. Burn the ISO to a USB stick as a raw disk image. On Linux, a command such as the following may suffice:
```
dd if=./holos-v0.0.7ga.5.iso of=/dev/sdX bs=1024k conv=sync
```
   Where `/dev/sdX` is the block device node for the USB stick.
3. Boot your computer from the USB stick and log in as root with no password.
4. Choose the live-mode or install option from the Grub Boot Menu
5. Note: If desirable you can run the installer script from live-mode, telling it which hard drive to install to (generally `sda` on HoloPorts). The following command will work on HoloPorts:
```
install-draft sda
```
   Once the installation has completed, the HoloPort will automatically reboot. Remove the USB stick and allow it to boot from the hard drive.

Step 2: Run the container 

Container run commands: 
```
docker run --name edgenode -dit -v $(pwd)/holo-data:/data ghcr.io/holo-host/edgenode
```

Step 3: Install a hApp from a configuration file:

1. Use ``` happ_config_file create ``` command to generate a happ config file template, or you could use `wget` to get the configuration file on your machine, e.g.:  
   `wget https://gist.github.com/zippy/28a93d63470256bde57738336a476e18`
2. Verify the configuration file using the `happ_config_file` tool:  
   `$ happ_config_file validate --input example_config.json`  
   This command will confirm that the structure and contents of the config file are valid.
3. Install the app:  
   `install_happ example_config.json`
4. Verify the installation from the output generated and by looking at the installed apps with:  
   `list_happs`

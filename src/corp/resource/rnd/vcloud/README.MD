# Intro
`vcloud` variables provide ability to control vCloud vApps and VMs via it's PowerShell API.

Please be sure to read `Prerequisites` section before using variables.
Please be sure to read `Usage` section before using variables.

# Prerequisites

For proper functioning of `vcloud` variables you will need to prepare Jenkins.

### Jenkins prerequisites

1. `PowerShell`, `SSH` and `WMI Windows Agents Plugin` plugins installed for connecting to agents
2. Credentials for accessing vCloud added to Jenkins.

### VM prerequisites

1. `Powershell 2+` installed on Windows agents.

# Usage

For `vcloud` variable usage you will need to add @Library annotation to the top of the Jenkinsfile and it would be good to import class that contain all methods you could use.

```
@Library('rnd-shared-library') _
import corp.resource.rnd.whitesource.vcloud.Vcloud()
```

Where 'rnd-shared-library' is a name of your shared library. `_` sign at the end will import all variables/classes from library, and `import corp.resource.rnd.whitesource.Whitesource` will help you to reduce amount of symbols you use to initialize a class.

In a place where you want to run a new vCloud operation you need to create vCloud class instance, and set up some vCloud related variables

```
def server          = "vcloud.server.fqdn"
def catalog         = "Catalog_name"
def org             = "Organization_name"
def ovdc            = "OVDC_name"

def cloud = new corp.resource.rnd.vcloud.Vcloud()

```

After that you will be able to use variables like steps in Jenkinsfile.

```
steps {
    script {
        def vAppName = 'predefined_name_or_earlier_Pipeline_variable'
        withCredentials([usernamePassword(credentialsId: 'vcloud_access_id_in_Jenkins_credentials', passwordVariable: 'vc_passwd', usernameVariable: 'vc_user')]) {
   	        cloud.vapp_stop(vc_user, vc_passwd, vAppName, server, org)
            echo "vApp stopped"
            cloud.vapp_remove(vc_user, vc_passwd, vAppName, server, org, ovdc)
       	    echo "vApp removed"
        }
    }
}
```

### List of available variables

Work is in progress.
### Pipeline example

```groovy
@Library('rnd-shared-library') _

def cloud = new corp.resource.rnd.vcloud.Vcloud()

pipeline {
    agent { node { label "windows" } }
    options {
        timestamps()
    	buildDiscarder logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '', numToKeepStr: '5')
    }
    parameters {
        string(name: 'vAppName', description: 'vApp name for removing', defaultValue: "" )
        string(name: 'server', description: 'vCloud Server full host name', defaultValue: "" )
        string(name: 'org', description: 'vCloud organization name', defaultValue: "" )
        string(name: 'ovdc', description: 'vCloud OVDC name', defaultValue: "" )
    }

    stages {
    	stage('Prepare vCloud Scripts') {
	        steps {
                script {
                    cleanWs()
		            // Work in progress, currently we have a some issues with running this on Linux docker PowerShell image
		            // cloud.prepare_vcloud_scripts()
                }
            }
        }
    	stage('vApp Remove') {
            steps {
                script {
    	            withCredentials([usernamePassword(credentialsId: 'vcloud-rnd-bot', passwordVariable: 'vc_passwd', usernameVariable: 'vc_user')]) {
            	        cloud.vapp_remove(vc_user, vc_passwd, vAppName, server, org, ovdc)
                    }
		            echo "vApp Removed: ${vAppName}"
                }
            }
	    }
    }
}
```

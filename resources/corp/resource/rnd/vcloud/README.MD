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
def server          = "vcloud.fqdn"
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

This is a basic full Pipeline example, currently it can be run only on windows slave agents

```groovy
@Library('rnd-shared-library') _

def cloud = new corp.resource.rnd.vcloud.vcloud()

pipeline {
    agent { node { label "windows" } }
    options {
        timestamps()
    	buildDiscarder logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '', numToKeepStr: '5')
    }
    parameters {
        string(name: 'vAppName', description: 'vApp name for creating', defaultValue: "" )
        string(name: 'vAppDescription', description: 'vApp default description, a reference to Jira or confluence page for vApp identification', defaultValue: "Default vApp description. Fill it, please for vApp identification" )
        string(name: 'template', description: 'The name of the template for cloning to the new vApp', defaultValue: "CI-Ansible-os-only" )
        string(name: 'catalog', description: 'vCloud Catalog name for template selection', defaultValue: "RND-Catalog-Name" )
        string(name: 'server', description: 'vCloud Server full host name', defaultValue: "vcloud.fqdn" )
        string(name: 'org', description: 'vCloud organization name', defaultValue: "RND" )
        string(name: 'ovdc', description: 'vCloud OVDC name', defaultValue: "OVDC-RND-01" )
    }

    stages {
    	stage('Prepare Workspace') {
	    steps {
                script {
                    cleanWs()
                }
	    }
        }
    	stage('vApp Create') {
            steps {
                script {
    	            withCredentials([usernamePassword(credentialsId: 'vcloud-username', passwordVariable: 'vcloud-passwd', usernameVariable: 'vcloud-user')]) {
            	    	cloud.vapp_create(vc_user, vc_passwd, vAppName, vAppDescription, server, org, ovdc, template, catalog)
                    }
		            echo "vApp Created: ${vAppName}"
                }
            }
	    }
    }
}
```

package corp.resource.rnd.vcloud

import groovy.transform.Field

@Field def script_name = 'script.ps1'
@Field def library_resource_path = 'corp\\resource\\rnd\\vcloud\\'
@Field def ps1_filename = 'vcloud_vapp.ps1'
@Field def PS_executable_path = "%SystemRoot%\\SysWOW64\\WindowsPowerShell\\v1.0\\powershell.exe"

def pwd_transition(vc_passwd) {
  vc_passwd = vc_passwd.replaceAll(/\)/,'`)')
  vc_passwd = vc_passwd.replaceAll(/\;/,'`;')
  vc_passwd = vc_passwd.replaceAll(/\"/,'`"')
  vc_passwd = vc_passwd.replaceAll(/\*/,'`*')
  return vc_passwd
}

def rnd_id() {
  Random random = new Random()
  return random.nextInt(10 ** 5)
}

def get_vcloud_lib() {
  def ps1lib_content = libraryResource (library_resource_path + ps1_filename)
  def ps1lib_name = ("$workspace\\"+rnd_id()+"-$ps1_filename").replace("\\", "/")
  writeFile(file: ps1lib_name, text: ps1lib_content)
  return ps1lib_name
}

def scriptGenerator(body) {
  def include_pslib_file = get_vcloud_lib()
  String templateContent = """
      . '$include_pslib_file'
      $body
  """
  run_script(templateContent)
}

def prepare_vcloud_scripts() {
  //if (isUnix()) {
  //  steps.sh label: 'pwsh', returnStdout: true, script: """
  //    yum upgrade -y
  //    curl https://packages.microsoft.com/config/rhel/6/prod.repo | tee /etc/yum.repos.d/microsoft.repo
  //    yum update -y powershell
  //  """
  //}
  scriptGenerator("Initialize-vCloud-Scripts")
}

def vapp_create(vc_user, vc_passwd, vAppName, vAppDescription, server, org, ovdc, template, catalog) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    New-vApp -Name "$vAppName" -Description "$vAppDescription" -Template "$template" -Catalog "$catalog" -Ovdc "$ovdc" -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def vapp_get_ips(vc_user, vc_passwd, vAppName, server, org, ip_json) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Get-vApp-IPs -Name "$vAppName" -User '$vc_user' -Passwd '$escaped_passwd' -Org '$org' -Server '$server' -Ip_Json '$ip_json'
  """
  scriptGenerator(body)
}

def vapp_remove(vc_user, vc_passwd, vAppName, server, org) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Remove-vApp -Name "$vAppName" -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def vapp_start(vc_user, vc_passwd, vAppName, server, org) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Start-vApp -Name "$vAppName" -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def vapp_stop(vc_user, vc_passwd, vAppName, server, org) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Stop-vApp -Name "$vAppName" -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def template_create(vc_user, vc_passwd, source_vAppName, description, template, catalog, server, org, ovdc) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    New-vAppTemplate -vAppName "$source_vAppName" -Description "$description" -TemplateName "$template" -CatalogName "$catalog" -Ovdc "$ovdc" -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def template_update(vc_user, vc_passwd, name, new_name, new_description, catalog, server, org) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Update-vAppTemplate -Name "$name" -NewDescription "$new_description" -NewName "$new_name"  -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def template_delete(vc_user, vc_passwd, template_name, server, org) {
  def escaped_passwd = pwd_transition(vc_passwd)
  def body = """
    Remove-vAppTemplate -Name "$template_name"  -User '$vc_user' -Passwd $escaped_passwd -Org '$org' -Server '$server'
  """
  scriptGenerator(body)
}

def run_script(body) {
  def run_name = ("$workspace\\"+rnd_id()+"-$script_name").replace("\\", "/")
  //echo body
  writeFile(file: run_name, text: body)
  if (isUnix()) { 
    /*
    steps.sh label: 'pwsh', returnStdout: true, script: """
    time `which pwsh` '$run_name'
    """
    */
      sh """
        echo "Starting the $run_name script"
        time `which pwsh` '$run_name'
      """
  } else {
    steps.bat label: 'bat', returnStdout: true, script: """
      @echo off
      $PS_executable_path $run_name -NonInteractive
    """
  }
}

return this

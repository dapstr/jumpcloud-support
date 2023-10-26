# InvokePester.ps1 is intended to be called directly as a file-function
# There are two parameter sets

Param(
    [Parameter(ParameterSetName = 'moduleValidation', Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 5)][switch]$ModuleValidation,
    [Parameter(ParameterSetName = 'dataTests', Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0)][ValidateNotNullOrEmpty()][System.String]$JumpCloudApiKey
    , [Parameter(ParameterSetName = 'dataTests', Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 1)][ValidateNotNullOrEmpty()][System.String]$JumpCloudApiKeyMsp
    , [Parameter(ParameterSetName = 'dataTests', Mandatory = $false, ValueFromPipelineByPropertyName = $true, Position = 1)][ValidateNotNullOrEmpty()][System.String]$JumpCloudMspOrg
    , [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, Position = 2)][System.String[]]$ExcludeTagList
    , [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, Position = 3)][System.String[]]$IncludeTagList
    , [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, Position = 4)][System.String]$RequiredModulesRepo = 'PSGallery'
)

# Load Get-Config.ps1
. "$PSScriptRoot/../../Deploy/Get-Config.ps1"

# Get list of tags and validate that tags have been applied
$PesterTests = Get-ChildItem -Path:($PSScriptRoot + '/*.Tests.ps1') -Recurse
$Tags = ForEach ($PesterTest In $PesterTests) {
    $PesterTestFullName = $PesterTest.FullName
    $FileContent = Get-Content -Path:($PesterTestFullName)
    $DescribeLines = $FileContent | Select-String -Pattern:([RegEx]'(Describe)')#.Matches.Value
    ForEach ($DescribeLine In $DescribeLines) {
        If ($DescribeLine.Line -match 'Tag') {
            $TagParameterValue = ($DescribeLine.Line | Select-String -Pattern:([RegEx]'(?<=-Tag)(.*?)(?=\s)')).Matches.Value
            @(":", "(", ")", "'") | ForEach-Object { If ($TagParameterValue -like ('*' + $_ + '*')) {
                    $TagParameterValue = $TagParameterValue.Replace($_, '')
                } }
            $TagParameterValue
        } Else {
            Write-Error ('Tag missing in "' + $PesterTestFullName + '" on line number "' + $DescribeLine.LineNumber + '" value "' + ($DescribeLine.Line).Trim() + '"')
        }
    }
}
# Filters on tags
$IncludeTags = If ($IncludeTagList) {
    $IncludeTagList
} Else {
    $Tags | Where-Object { $_ -notin $ExcludeTags } | Select-Object -Unique
}

# Determine the parameter set path
if ($PSCmdlet.ParameterSetName -eq 'moduleValidation') {
    $IncludeTags = "ModuleValidation"
    $PesterRunPaths = @(
        "$PSScriptRoot/ModuleValidation/"
    )
} elseif ($PSCmdlet.ParameterSetName -eq 'dataTests') {
    if ($env:CI) {
        $env:JCAPIKEY = $env:PESTER_APIKEY
        Connect-JCOnline -JumpCloudApiKey:($env:JCAPIKEY)  -force
        $PesterTestsPaths = Get-ChildItem -Path $PSScriptRoot -Filter *.Tests.ps1 -Recurse | Where-Object size -GT 0 | Sort-Object -Property Name
        $counter = [pscustomobject] @{ Value = 0 }
        $groupSize = 30
        $PesterGroups = $PesterTestsPaths | Group-Object -Property { [math]::Floor($counter.Value++ / $groupSize) }
        $jobMatrixSet = @{
            0 = $PesterGroups[0].Group.FullName
            1 = $PesterGroups[1].Group.FullName
            2 = $PesterGroups[2].Group.FullName
        }
        Write-Host "[status] Running CI job group $env:job_group"
        $PesterRunPaths = $jobMatrixSet[[int]$($env:job_group)]
    } else {
        $PesterRunPaths = @(
            "$PSScriptRoot"
        )
    }
    # For online tests we need to run setup org and generate resources within an organization
    # Load DefineEnvironment
    #. ("$PSScriptRoot/DefineEnvironment.ps1") -JumpCloudApiKey:($JumpCloudApiKey) -JumpCloudApiKeyMsp:($JumpCloudApiKeyMsp) -RequiredModulesRepo:($RequiredModulesRepo)
    # Load SetupOrg
    if ("MSP" -in $IncludeTags) {
        Write-Host ('[status] MSP Tests setting API Key, OrgID')
        $env:JCAPIKEY = $env:PESTER_MSP_APIKEY
        $env:JCOrgId = $env:PESTER_ORGID
        $env:JCProviderID = $env:PESTER_PROVIDER_ID
        # force import module
        Import-Module $FilePath_psd1 -Force
        Connect-JCOnline -JumpCloudApiKey:($env:PESTER_MSP_APIKEY) -JumpCloudOrgId:($env:PESTER_ORGID) -force
        # . ("$PSScriptRoot/SetupOrg.ps1") -JumpCloudApiKey:($JumpCloudApiKey) -JumpCloudApiKeyMsp:($JumpCloudApiKeyMsp) -JumpCloudMspOrg:($JumpCloudMspOrg)
    } else {
        #Write-Host ('[status]Setting up org: ' + "$PSScriptRoot/SetupOrg.ps1")
        #. ("$PSScriptRoot/SetupOrg.ps1") -JumpCloudApiKey:($JumpCloudApiKey) -JumpCloudApiKeyMsp:($JumpCloudApiKeyMsp)
    }
}
# Load private functions
Write-Host ('[status]Load private functions: ' + "$PSScriptRoot/../Private/*.ps1")
Get-ChildItem -Path:("$PSScriptRoot/../Private/*.ps1") -Recurse | ForEach-Object { . $_.FullName }
# Load HelperFunctions
Write-Host ('[status]Load HelperFunctions: ' + "$PSScriptRoot/HelperFunctions.ps1")
. ("$PSScriptRoot/HelperFunctions.ps1")

# Set the test result directory:
$PesterResultsFileXmldir = "$PSScriptRoot/test_results/"
# create the directory if it does not exist:
if (-not (Test-Path $PesterResultsFileXmldir)) {
    New-Item -Path $PesterResultsFileXmldir -ItemType Directory
}


# define pester configuration
$configuration = New-PesterConfiguration
$configuration.Run.Path = $PesterRunPaths
$configuration.Should.ErrorAction = 'Continue'
$configuration.CodeCoverage.Enabled = $true
$configuration.testresult.Enabled = $true
$configuration.testresult.OutputFormat = 'JUnitXml'
$configuration.Filter.Tag = $IncludeTags
$configuration.Filter.ExcludeTag = $ExcludeTagList
$configuration.CodeCoverage.OutputPath = ($PesterResultsFileXmldir + 'coverage.xml')
$configuration.testresult.OutputPath = ($PesterResultsFileXmldir + 'results.xml')

Write-Host ("[RUN COMMAND] Invoke-Pester -Path:('$PSScriptRoot') -TagFilter:('$($IncludeTags -join "','")') -ExcludeTagFilter:('$($ExcludeTagList -join "','")') -PassThru") -BackgroundColor:('Black') -ForegroundColor:('Magenta')
# Run Pester tests
Invoke-Pester -Configuration $configuration

$PesterTestResultPath = (Get-ChildItem -Path:("$($PesterResultsFileXmldir)")).FullName | Where-Object { $_ -match "results.xml" }
If (Test-Path -Path:($PesterTestResultPath)) {
    [xml]$PesterResults = Get-Content -Path:($PesterTestResultPath)
    If ($PesterResults.ChildNodes.failures -gt 0) {
        Write-Error ("Test Failures: $($PesterResults.ChildNodes.failures)")
    }
    If ($PesterResults.ChildNodes.errors -gt 0) {
        Write-Error ("Test Errors: $($PesterResults.ChildNodes.errors)")
    }
} Else {
    Write-Error ("Unable to find file path: $PesterTestResultPath")
}
Write-Host -ForegroundColor Green '-------------Done-------------'
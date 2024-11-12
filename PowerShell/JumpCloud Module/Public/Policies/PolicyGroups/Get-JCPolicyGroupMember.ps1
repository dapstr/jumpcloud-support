Function Get-JCPolicyGroupMember {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            HelpMessage = "The ID of the JumpCloud policy group to query and return members of"
        )]
        [System.String]
        $PolicyGroupID
    )
    begin {
        if ([System.String]::IsNullOrEmpty($JCAPIKEY)) {
            Connect-JCOnline
        }
        $URL = "$JCUrlBasePath/api/v2/policygroups/$PolicyGroupID/membership"
    }
    process {
        $response = Invoke-JCApi -Method:('GET') -Paginate:($true) -Url:($URL)

        If ('NoContent' -in $response.PSObject.Properties.Name) {
            $policyMemberList = $null
        } else {
            $policyMemberList = New-Object System.Collections.ArrayList
            foreach ($policy in $response) {
                # return the values by getting the policy individually
                $policyResult = Get-JCPolicy -PolicyID $policy.id
                $policyMemberList.Add($policyResult) | Out-Null
            }
        }

    }
    end {
        return $policyMemberList
    }
}
@{
    Rules = @{
        PSUseCompatibleSyntax = @{
            # This turns the rule on (setting it to false will turn it off)
            Enable = $true

            # Simply list the targeted versions of PowerShell here
            TargetVersions = @(
                '5.0',
                '6.0',
                '7.0'
            )
        }
    }
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
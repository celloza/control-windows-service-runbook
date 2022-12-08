<#
.SYNOPSIS
  Stop or Start a Windows Service using a Hybrid Runbook Worker

.DESCRIPTION
  This runbook allows you to control (stop or start) a Windows Service.

  It specifically waits for the service to reach the target state ('Running' if 'action' is 'stop', 'Stopped' if 'action' is 'start') within
  the provided timespan. If waiting for the state times out, an exception is thrown which can control the flow (as it was originally intended)
  in a LogicApp.

  Exit codes are as follows:

  0 - The script executed succesfully.
  1 - Invalid parameters specified.
  2 - Service was in an invalid state to perform the operation.
  3 - A timeout occurred while trying to perform the operation.
  4 - No or multiple services found using the provided name.
  99 - Unhandled exception.

  The output is formatted as JSON for easy consumption in a LogicApp. Sample output is provided below:

  {
	"success": true,
	"message": "Service started successfully.",
	"errorCode": 0
  }

  To see verbose output, make sure to set the 'Log verbose records' in your Azure Runbook (under Logging and Tracing) to 'On'.

.PARAMETER Action
   Mandatory, no default set.
   The action to take on the service. Valid options are 'start' or 'stop'. 
   Only services that are Running can be stopped and only services that are Stopped can be started, otherwise an exception is generated. If this
   is not regarded as a failure condition in your environment, monitor for exit code 2.

.PARAMETER ServiceName
   Mandatory, no default set.
   The name of the Windows Service that you want to perform the action on.
   Although you can specify a wildcard (i.e. 'App*' will match AppIdSvc and AppMgmt), the script will generate an error if it finds more than one
   service. Monitor for exit code 4 if this is unintended.

.PARAMETER TimeOutSeconds
   Mandatory, no default set.
   The time to wait (in seconds) for the service to make the requested state change.  
   If the service does not successfully change its state within this timespan, an exception will be generated. Monitor for exit code 3.

.NOTES
   AUTHOR: Marcel du Preez
   LASTEDIT: December 8, 2022
#>

Param
(
  [Parameter (Mandatory= $true)]
  [string] $Action,
  [Parameter (Mandatory= $true)]
  [string] $ServiceName,
  [Parameter (Mandatory= $true)]
  [int] $TimeOutSeconds
)

function ProvideResponse()
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory= $true)]
		[string]$OutputMessage,
		[Parameter(Mandatory= $false)]
		[int]$ErrorCode
	)

	$payload = @{
		success = ($errorCode -eq 0)
		message = $OutputMessage
		exitCode = $errorCode
	}

	Write-Output (ConvertTo-Json $payload)
}

$GLOBAL:ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

Write-Verbose "Runbook started."

# Parameter checking
if(($Action.ToLowerInvariant() -ne 'start') -and ($Action.ToLowerInvariant() -ne 'stop'))
{
	$errorMessage = "Action can only be 'start' or 'stop'"
	ProvideResponse -OutputMessage $errorMessage -ErrorCode 1
	Write-Error $errorMessage -ErrorAction Continue
	throw $errorMessage
}

if($TimeOutSeconds -lt 1)
{
	$errorMessage = "Timeout in seconds cannot be less than 1."
	ProvideResponse -OutputMessage $errorMessage -ErrorCode 1
	Write-Error $errorMessage -ErrorAction Continue 
	throw $errorMessage
}

$timeSpan = New-Object Timespan 0,0,$TimeOutSeconds
Write-Verbose "Service to $Action : $ServiceName"
Write-Verbose "Checking if service exists..."
$service = Get-Service $ServiceName -ErrorAction SilentlyContinue

if($service.Length -gt 1)
{
	$errorMessage = "Found more than one service with the supplied ServiceName parameter."
	ProvideResponse -OutputMessage $errorMessage -ErrorCode 4
	Write-Error $errorMessage -ErrorAction Continue 
	throw $errorMessage
}
elseif($service.Length -eq 1) 
{
	Write-Verbose "Found service. Current state is: $($service.Status)"

	if($Action -eq 'start')
	{
		if($service.Status -eq [ServiceProcess.ServiceControllerStatus]::Running)
		{
			$warningMessage = "Service is already running. No action performed."
			ProvideResponse -OutputMessage $warningMessage -ErrorCode 0
			Write-Warning $warningMessage 
			
		}
		elseif($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped)
		{
			$errorMessage = "Cannot start a service that is $($service.Status)"
			ProvideResponse -OutputMessage $errorMessage -ErrorCode 2
			Write-Error $errorMessage -ErrorAction Continue 
			throw $errorMessage
		}
		else 
		{
			Write-Verbose "Starting $Service..."

			try 
			{
				$service | Start-Service
				(Get-Service $ServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, $timeSpan)
				$successMessage = "Service started successfully."
				Write-Verbose $successMessage
				ProvideResponse -OutputMessage $successMessage -ErrorCode 0
			}
			catch [System.ServiceProcess.TimeoutException] 
			{
				$errorMessage = "The service did not $Action within the specified timeout of $timeOutSeconds seconds."
				ProvideResponse -OutputMessage $errorMessage -ErrorCode 3
				Write-Error $errorMessage -ErrorAction Continue 
				throw $errorMessage
			}
			catch 
			{
				ProvideResponse -OutputMessage $_.Exception -ErrorCode 99
				Write-Error -Message $_.Exception -ErrorAction Continue
				throw $_.Exception
			}
		}
	}

	if($Action -eq 'stop')
	{
		if($service.Status -eq [ServiceProcess.ServiceControllerStatus]::Stopped)
		{
			$warningMessage = "Service is already stopped. No action performed."
			ProvideResponse -OutputMessage $warningMessage -ErrorCode 0
			Write-Warning $warningMessage 
			
		}
		elseif($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running)
		{
			$errorMessage = "Cannot stop a service that is $($service.Status)"
			ProvideResponse -OutputMessage $errorMessage -ErrorCode 2
			Write-Error $errorMessage -ErrorAction Continue
			throw $errorMessage
		}
		else 
		{
			try
			{
				Write-Verbose "Stopping $ServiceName..."
				$service | Stop-Service -NoWait
				(Get-Service $ServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, $timeSpan)
				$successMessage = "Service stopped successfully."
				Write-Verbose $successMessage
				ProvideResponse -OutputMessage $successMessage -ErrorCode 0
			}
			catch [System.ServiceProcess.TimeoutException] 
			{
				$errorMessage = "The service did not $Action within the specified timeout of $timeOutSeconds seconds."
				ProvideResponse -OutputMessage $errorMessage -ErrorCode 3
				Write-Error $errorMessage -ErrorAction Continue
				throw $errorMessage
			}
			catch 
			{
				ProvideResponse -OutputMessage $_.Exception -ErrorCode 99
				Write-Error -Message $_.Exception -ErrorAction Continue
				throw $_.Exception
			}
		}
	}
}
else
{
	$errorMessage = "Could not find a service called '$ServiceName'."
	ProvideResponse -OutputMessage $errorMessage -ErrorCode 4
	Write-Error $errorMessage -ErrorAction Continue
	throw $errorMessage
}

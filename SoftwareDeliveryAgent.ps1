### CyberBrain.pw Software Delivery Agent

$DisplayName = "CyberBrain.pw Software Delivery Agent"
$ThisProjectName = "SoftwareDeliveryAgent"

################################################

$ThisScriptName = $MyInvocation.MyCommand.Name
$ThisScriptPath = split-path -parent $MyInvocation.MyCommand.Definition

###########################################################################################################################################################

### Paths

# Source
$SOURCE="\\storage.skynet.tld"
$SOURCE_PACKAGES="$SOURCE\deployment$\packages"
$SOURCE_STATE="$SOURCE\sda_state$\$env:COMPUTERNAME.state"
$SOURCE_QUEUE="$SOURCE\deployment$\queue\$env:COMPUTERNAME.queue"

###########################################################################################################################################################

# Agent
$AGENT_DATA="$env:ProgramData\$ThisProjectName"
$AGENT_DEBUG="$AGENT_DATA\debug.txt"
$AGENT_QUEUE="$AGENT_DATA\queue.list"
$AGENT_LOCK_MAINTENANCE="$AGENT_DATA\maintenance.lock"
$AGENT_LOCK_EXECUTION="$AGENT_DATA\execution.lock"

# Chocolatey
$CHOCO_DEBUG="$AGENT_DATA\chocolatey.txt"

###########################################################################################################################################################

### Check

# Parameters: module
if ($args[0]) {
	$MODULE=$args[0]
} else {
	$MODULE="help"
}

###########################################################################################################################################################
###########################################################################################################################################################


### FUNCTIONS

$TAG = "Global"

################################################

function debug_log{
	Param(
		[string]$TAG,
		[string]$MESSAGE
	)
	#####

	$DATE_LOG = get-date -uformat "%Y.%m.%d %T %Z"
	if (Test-Path "$AGENT_DEBUG") {"${DATE_LOG} ## ${TAG} ## ${MESSAGE}" | Tee-Object -FilePath "$AGENT_DEBUG" -Append}
}

function queue_relauncher {
	# Checkking if chocolatey is installed
	check_choco
	
	# Saving state
	agent_state_save

	# Background queue tasks start
	if ((Get-WmiObject Win32_Process -Filter "CommandLine Like '%$ThisScriptName queue_local%'" | Select-Object CommandLine | Measure).Count -eq 0) {
		Start-Process powershell -Argumentlist "$ThisScriptPath\$ThisScriptName queue_local"
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Local queue manager is already running. Skipping..."
	}
	if ((Get-WmiObject Win32_Process -Filter "CommandLine Like '%$ThisScriptName queue_remote%'" | Select-Object CommandLine | Measure).Count -eq 0) {
		Start-Process powershell -Argumentlist "$ThisScriptPath\$ThisScriptName queue_remote"
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Remote queue manager is already running. Skipping..."
	}
}

################################################

function check_choco {
	if ((Get-Command "choco.exe" -ErrorAction SilentlyContinue) -eq $null) {
		debug_log -TAG "$TAG" -MESSAGE "Chocolatey is not found in your PATH. Attempting to install..."
		[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) | Write-Host; refreshenv | Write-Host;
	}
}

function agent_state_save {
	if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
		debug_log -TAG "$TAG" -MESSAGE "Saving parameters is NOT allowed to user in DEBUG mode"
	} else {
		choco list --local-only -r | Set-Content "$SOURCE_STATE" | Out-Null
	}
}

################################################

## Tasks

function agent_task_add {
	Param(
		[string]$TASK
	)
	#####

	$TAG = "Local Queue"

	$ID=Get-Date -UFormat %s
	"$ID $TASK" >> $AGENT_QUEUE

	debug_log -TAG "$TAG" -MESSAGE "Task added: $ACTION $TARGET"
}

function agent_task_remove {
	Param(
		[string]$TASK_WITH_ID
	)
	#####

	$TAG = "Local Queue"

	Get-Content $AGENT_QUEUE | Where {$_ -ne $TASK_WITH_ID} | Out-File $AGENT_QUEUE

	debug_log -TAG "$TAG" -MESSAGE "Task removed: $ACTION $TARGET"
}

function agent_task_execute {
	Param(
		[string]$ACTION,
		[string]$TARGET
	)
	#####

	$TAG = "Task Execution"

	# Create execution lock
	New-Item -Path "$AGENT_LOCK_EXECUTION" -ItemType "file" -Force | Out-Null

	################################################

	$Die=$false

	# Parameters: action
	if (-not ($ACTION -eq 'install' -or $ACTION -eq 'uninstall' -or $ACTION -eq 'upgrade')) {
		debug_log -TAG "$TAG" -MESSAGE "ERROR: Incorrect action defined!"
		$Die=$true
	}

	# Parameters: target
	if (-not ($TARGET)) {
		debug_log -TAG "$TAG" -MESSAGE "ERROR: No package defined!"
		$Die=$true
	} 

	################################################

	# Exit on error(s) or run task
	if (-not $Die) {   
		$COUNT_INSTALLED = ((choco list --local-only -r | ForEach-Object {$_.split("|")[0]}) | Where-Object -FilterScript {$_ -eq "${TARGET}"} | Measure).Count

		if (($COUNT_INSTALLED -gt 0 -and $ACTION -eq 'install') -or ($COUNT_INSTALLED -eq 0 -and $ACTION -eq 'uninstall')) {
			debug_log -TAG "$TAG" -MESSAGE "Skipping: $ACTION $TARGET"
		} else {
			debug_log -TAG "$TAG" -MESSAGE "Starting: $ACTION $TARGET"

			## WORKFLOW
			if (Test-Path "$CHOCO_DEBUG") {
				choco $ACTION $TARGET -v -y --no-progress | Tee-Object -FilePath "$CHOCO_DEBUG" -Append
			} else{
				choco $ACTION $TARGET -r -y --no-progress | Out-Null
			}

			debug_log -TAG "$TAG" -MESSAGE "Finished: $ACTION $TARGET"
			agent_state_save
		}
	}

	################################################

	# Remove execution lock
	Remove-Item -Path "$AGENT_LOCK_EXECUTION" -Force | Out-Null
}

################################################

## Queues

function agent_queue_local {
	Param(
		[string]$QUEUE
	)
	#####

	$TAG = "Local Queue"

	# Create local queue file if not exist
	if (-Not (Test-Path "$QUEUE")) { New-Item -Path "$QUEUE" -ItemType "file" -Force | Out-Null }

	# Local queue check
	Get-Content "$QUEUE" -Wait | ForEach-Object {
		$AGENT_QUEUE_TASK="$_"

		if ($AGENT_QUEUE_TASK.Contains(" ")) {

			$ID=($AGENT_QUEUE_TASK).Split(" ")[0]
			$ACTION=($AGENT_QUEUE_TASK).Split(" ")[1]
			$TARGET=($AGENT_QUEUE_TASK).Split(" ")[2]

			if ($ID -and $ACTION -and $TARGET) {
				debug_log -TAG "$TAG" -MESSAGE "Processing: $ACTION $TARGET"
				while (Test-Path "$AGENT_LOCK_EXECUTION" -or Test-Path "$AGENT_LOCK_MAINTENANCE"){
					debug_log -TAG "$TAG" -MESSAGE "Waiting for free task window"
					Start-Sleep -s 15
				}
				# Execute task
				agent_task_execute -ACTION "$ACTION" -TARGET "$TARGET"
			} else {
				debug_log -TAG "$TAG" -MESSAGE "Incorrect: $AGENT_QUEUE_TASK"
			}
		}
		
		# Remove task
		agent_task_remove -TASK_WITH_ID "$AGENT_QUEUE_TASK"
	} | Out-Null
}

function agent_queue_remote {
	Param(
		[string]$QUEUE
	)
	#####

	$TAG = "Remote Queue"

	# Remote queue check
	Get-Content "$QUEUE" -wait | ForEach-Object {
		$AGENT_QUEUE_TASK="$_"
   
		if ($AGENT_QUEUE_TASK.Contains(" ")) {

			$ID=($AGENT_QUEUE_TASK).Split(" ")[0]
			$ACTION=($AGENT_QUEUE_TASK).Split(" ")[1]
			$TARGET=($AGENT_QUEUE_TASK).Split(" ")[2]

			if ($ID -and $ACTION -and $TARGET) {
				debug_log -TAG "$TAG" -MESSAGE "Processing: $ACTION $TARGET"
				agent_task_add -TASK "$ACTION $TARGET"
			} else {
				debug_log -TAG "$TAG" -MESSAGE "Incorrect: $AGENT_QUEUE_TASK"
			}
		}
	} | Out-Null
}

################################################

function agent_maintenance {
	$TAG = "Maintenance"

	queue_relauncher
}

###########################################################################################################################################################
###########################################################################################################################################################

### Local queue execution
if ($MODULE -eq 'queue_local') {
	if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
		debug_log -TAG "$TAG" -MESSAGE "Local queue manager is NOT allowed to user in DEBUG mode"
		Break
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Local queue manager is starting..."
	}

	# Endless cycle
	while ($true) {
		agent_queue_local -QUEUE "$AGENT_QUEUE"
		Start-Sleep -s 10
		debug_log -TAG "$TAG" -MESSAGE "Local queue manager is restarting..."
	}

################################################

### Remote queue execution
} elseif ($MODULE -eq 'queue_remote') {
	if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
		debug_log -TAG "$TAG" -MESSAGE "Remote queue manager is NOT allowed to user in DEBUG mode"
		Break
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Remote queue manager is starting..."
	}

	# Endless cycle
	while ($true) {
		agent_queue_remote -QUEUE "$SOURCE_QUEUE"
		Start-Sleep -s 10
		debug_log -TAG "$TAG" -MESSAGE "Remote queue manager is restarting..."
	}

################################################

### Maintenance task
} elseif ($MODULE -eq 'maintenance') {
	if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
		debug_log -TAG "$TAG" -MESSAGE "Maintenance task is NOT allowed to user in DEBUG mode, run it via Windows Task Scheduler"
		Break
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Maintenance task is starting..."
	}
	 
	while (Test-Path "$AGENT_LOCK_EXECUTION" -or Test-Path "$AGENT_LOCK_MAINTENANCE"){
		debug_log -TAG "$TAG" -MESSAGE "Maintenance task is waiting for free task window..."
		Start-Sleep -s 15
	}

	# Create maintenance lock
	New-Item -Path "$AGENT_LOCK_MAINTENANCE" -ItemType "file" -Force | Out-Null
	################################################
	
	# Maintenance task
	agent_maintenance

	################################################
	# Remove maintenance lock
	Remove-Item -Path "$AGENT_LOCK_MAINTENANCE" -Force | Out-Null

###########################################################################################################################################################

### Startup and setup
} elseif ($MODULE -eq 'start') {
	if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
		debug_log -TAG "$TAG" -MESSAGE "Agent startup is NOT allowed to user in DEBUG mode"
		Break
	} else {
		debug_log -TAG "$TAG" -MESSAGE "Invoking agent..."
	}

	# Dirs
	if (-not (Test-Path "$AGENT_DATA")) {New-Item -Path "$AGENT_DATA" -ItemType directory | Out-Null}

	# Purge lockfiles
	Remove-Item -Path "$AGENT_LOCK_EXECUTION" -Force | Out-Null
	Remove-Item -Path "$AGENT_LOCK_MAINTENANCE" -Force | Out-Null
	
	# Background queue tasks start
	queue_relauncher

################################################

### Shutdown
} elseif ($MODULE -eq 'stop') {
	debug_log -TAG "$TAG" -MESSAGE "Shutting down background processes..."

	# Background queue tasks kill
	wmic Path win32_process Where "CommandLine Like `'%$ThisScriptName queue%`'" Call Terminate | Out-Null
	
###########################################################################################################################################################

### Help =)
} elseif ($MODULE -eq 'help') {
	""
	"$ThisProjectName`. YOU NEED ADMINISTRATIVE RIGHTS TO RUN THIS SCRIPT!"
	""
	" Help:"
	" - You can enable debug mode by creating an empty text file named $AGENT_DEBUG - this will log messages to $AGENT_DEBUG. To exit debug mode - remove that file."
	""

###########################################################################################################################################################

} else {
	debug_log -TAG "$TAG" -MESSAGE "ERROR: Incorrect action defined!"
	Break
}
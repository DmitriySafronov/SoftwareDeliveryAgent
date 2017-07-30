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
$AGENT_STATE="$AGENT_DATA\state"
$AGENT_CACHE="$AGENT_DATA\cache"
$AGENT_QUEUE="$AGENT_DATA\local.queue"
$AGENT_LOCK_MAINTENANCE="$AGENT_DATA\maintenance.lock"

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

## State

function agent_state_save {
    if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"Saving parameters is NOT allowed to user in DEBUG mode" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    } else {
        New-Item -Path "$SOURCE_STATE" -ItemType "file" -Force | Out-Null
		Get-ChildItem "$AGENT_STATE" -Name | Set-Content "$SOURCE_STATE" | Out-Null
	}

}

################################################

## Tasks

function agent_task_add {
	Param(
		[string]$TASK
	)
	#####
	
    $ID=Get-Date -UFormat %s
	"$ID $TASK" >> $AGENT_QUEUE
}

function agent_task_remove {
	Param(
		[string]$TASK_WITH_ID
	)
	#####

    Get-Content $AGENT_QUEUE | Where {$_ -ne $TASKTASK_WITH_ID} | Out-File $AGENT_QUEUE
}

################################################

## Queues

function agent_queue_local {
	Param(
		[string]$QUEUE
	)
	#####

	# Create local queue file if not exist
	if (-Not (Test-Path "$QUEUE")) { New-Item -Path "$QUEUE" -ItemType "file" -Force | Out-Null }

    $QUEUE_DONE=@()
    # Local queue check
    Get-Content "$QUEUE" -Wait | ForEach-Object {
        if ($_ -NotIn $QUEUE_DONE) {
            $AGENT_QUEUE_TASK="$_"

            if ($AGENT_QUEUE_TASK.Contains(" ")) {

                $ID=($AGENT_QUEUE_TASK).Split(" ")[0]
                $ACTION=($AGENT_QUEUE_TASK).Split(" ")[1]
                $TARGET=($AGENT_QUEUE_TASK).Split(" ")[2]

                if ($ACTION -eq 'pin') {
                    if (-Not (Test-Path "$AGENT_STATE\$TARGET.pinned")) {
                        if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID pinning $TARGET" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                        New-Item -Path "$AGENT_STATE\$TARGET.pinned" -ItemType "file" -Force | Out-Null
                    }
                } elseif ($ACTION -eq 'unpin') {
                    if (Test-Path "$AGENT_STATE\$TARGET.pinned") {
                        if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID unpinning $TARGET" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                        Remove-Item -Path "$AGENT_STATE\$TARGET.pinned" -Force | Out-Null
                    }
                }

                if ((($ACTION -eq 'install') -or ($ACTION -eq 'pin')) -and (-Not (Test-Path "$AGENT_STATE\$TARGET.installed")) -and (-Not (Test-Path "$AGENT_STATE\$TARGET.working"))) {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID marking $TARGET for installation" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $ACTION='install'
                    $TASK_RUN=$true
                } elseif ((($ACTION -eq 'uninstall') -or ($ACTION -eq 'unpin'))  -and (Test-Path "$AGENT_STATE\$TARGET.installed") -and (-Not (Test-Path "$AGENT_STATE\$TARGET.working"))) {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID marking $TARGET for uninstallation" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $ACTION='uninstall'
                    $TASK_RUN=$true
                } elseif ((($ACTION -eq 'cache') -or ($ACTION -eq 'pin')) -and (-Not (Test-Path "$AGENT_STATE\$TARGET.cached")) -and (-Not (Test-Path "$AGENT_STATE\$TARGET.working"))) {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID marking $TARGET for downloading" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $ACTION='cache'
                    $TASK_RUN=$true
                } elseif ((($ACTION -eq 'clean') -or ($ACTION -eq 'unpin')) -and (Test-Path "$AGENT_STATE\$TARGET.cached") -and (-Not (Test-Path "$AGENT_STATE\$TARGET.working"))) {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID marking $TARGET for cleaning" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $ACTION='clean'
                    $TASK_RUN=$true
                } elseif (($ACTION -eq 'check') -and (-Not (Test-Path "$AGENT_STATE\$TARGET.working"))) {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   + $ID marking $TARGET for checking" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $TASK_RUN=$true
                 } else {
                    if (Test-Path "$AGENT_DATA\debug.txt") {"Q   - $ID no more $ACTION for $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                    $TASK_RUN=$false
                }

                if ($TASK_RUN) {
                    agent_execute_task -ACTION "$ACTION" -TARGET "$TARGET"
                    agent_state_save
                }
            }

            $QUEUE_DONE+=$AGENT_QUEUE_TASK
            agent_task_remove -TASK_WITH_ID "$ID $ACTION $TARGET"
        }
    } | Out-Null
}

function agent_queue_remote {
	Param(
		[string]$QUEUE
	)
	#####

    $QUEUE_DONE=@()
    # Remote queue check
    Get-Content "$QUEUE" -wait | ForEach-Object {
	    if ($_ -NotIn $QUEUE_DONE) {
			$AGENT_QUEUE_TASK="$_"
   
			if ($AGENT_QUEUE_TASK.Contains(" ")) {
				$TASK_RUN=$false

				$ID=($AGENT_QUEUE_TASK).Split(" ")[0]
				$ACTION=($AGENT_QUEUE_TASK).Split(" ")[1]
				$TARGET=($AGENT_QUEUE_TASK).Split(" ")[2]

				if ($ID -and $ACTION -and $TARGET) {
					if (Test-Path "$AGENT_DATA\debug.txt") {"R   + Queued: $ID $ACTION $TARGET" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
					agent_task_add -TASK "$ACTION $TARGET"
				} else {
					if (Test-Path "$AGENT_DATA\debug.txt") {"R   - Incorrect: $AGENT_QUEUE_TASK" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
				}
			}

			$QUEUE_DONE+=$AGENT_QUEUE_TASK
		}
	} | Out-Null
}

################################################

# Check pinned
	
function agent_check_pinned {
    $AGENT_PINNED=Get-ChildItem "$AGENT_STATE" -Name -Filter *.pinned
    if ($AGENT_PINNED) {
    $PINNED_TASK_ARRAY=@()
        foreach ($PINNED in $AGENT_PINNED) {
            $DOT=($PINNED).LastIndexOf(".")
            $PINNED_TASK=($PINNED).Substring(0,$DOT)
            $PINNED_TASK_ARRAY+=$PINNED_TASK
        }
    }

    $AGENT_INSTALLED=Get-ChildItem "$AGENT_STATE" -Name -Filter *.installed
    if ($AGENT_INSTALLED) {
    $INSTALLED_TASK_ARRAY=@()
        foreach ($INSTALLED in $AGENT_INSTALLED) {
            $DOT=($INSTALLED).LastIndexOf(".")
            $INSTALLED_TASK=($INSTALLED).Substring(0,$DOT)
            $INSTALLED_TASK_ARRAY+=$INSTALLED_TASK
        }
    }

    $AGENT_SUSPICIOUS=$INSTALLED_TASK_ARRAY | Where-Object {$_ -In $PINNED_TASK_ARRAY}
        foreach ($SUSPICIOUS in $AGENT_SUSPICIOUS) {
            if (Test-Path "$AGENT_DATA\debug.txt") {"C   + marking $SUSPICIOUS for checking..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            agent_task_add -TASK "check $SUSPICIOUS"
        }

    $AGENT_NOTINSTALLED=$PINNED_TASK_ARRAY | Where-Object {$_ -NotIn $INSTALLED_TASK_ARRAY}
        foreach ($NOTINSTALLED in $AGENT_NOTINSTALLED) {
            if (Test-Path "$AGENT_DATA\debug.txt") {"C   + marking $SUSPICIOUS for installation..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            agent_task_add -TASK "install $NOTINSTALLED"
        }

}

################################################

function agent_execute_task {
	Param(
		[string]$ACTION,
		[string]$TARGET
	)
	#####
	
    # Parameters: subtasks
    $PKG_download=$true
    $PKG_install=$false
    $PKG_check=$false
    $PKG_uninstall=$false
    $PKG_clean=$true
    $PKG_pin=$false

    if ($ACTION -eq 'install') {
        $PKG_install=$true
    } elseif ($ACTION -eq 'uninstall') {
        $PKG_uninstall=$true
    } elseif ($ACTION -eq 'cache') {
        $PKG_clean=$false
    } elseif ($ACTION -eq 'clean') {
        $PKG_download=$false
    } elseif ($ACTION -eq 'check') {
        $PKG_check=$true
    } else {
        if (Test-Path "$AGENT_DATA\debug.txt") {"  W   ! ERROR: Incorrect action defined!" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        $Die=$true
    }

    # Parameters: package
    if (-Not($TARGET)) {
        if (Test-Path "$AGENT_DATA\debug.txt") {"  W   ! ERROR: No package defined!" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        $Die=$true
    } else {
        if (Test-Path "$AGENT_STATE\$TARGET.pinned") {
            $PKG_pin=$true
        }
    }

    ################################################

    # Exit on error(s)
    if ($Die) {
        Return
    }

    ################################################

    # Create temporary package lock
    New-Item -Path "$AGENT_STATE\$TARGET.working" -ItemType "file" -Force | Out-Null

    ################################################

    ## Package action
    $PKG_NextStage=$true

    # Package load
    if ($PKG_download -and $PKG_NextStage) {
        if (Test-Path "$SOURCE_PACKAGES\$TARGET") {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + downloading $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            robocopy "$SOURCE_PACKAGES\$TARGET" "$AGENT_CACHE\$TARGET" /MIR | Out-Null
            New-Item -Path "$AGENT_STATE\$TARGET.cached" -ItemType "file" -Force | Out-Null
        } else {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   - nothing to download ($TARGET)..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            $PKG_NextStage=$false
        }
    }

    # Package install
    if ($PKG_install -and $PKG_NextStage) {
        if (Test-Path "$AGENT_CACHE\$TARGET\run.ps1") {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + installing $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            powershell "$AGENT_CACHE\$TARGET\run.ps1 install" | Out-Null
            New-Item -Path "$AGENT_STATE\$TARGET.installed" -ItemType "file" -Force | Out-Null
			if ($lastexitcode = 0) {
				$PKG_NextStage=$false
            } else {
                New-Item -Path "$AGENT_STATE\$TARGET.installed" -ItemType "file" -Force | Out-Null
            }
        } else {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   - nothing to install ($TARGET)..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            $PKG_NextStage=$false
        }
    }

    # Package check
    if ($PKG_check -and $PKG_NextStage) {
        if (Test-Path "$AGENT_CACHE\$TARGET\run.ps1") {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + checking $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            powershell "$AGENT_CACHE\$TARGET\run.ps1 check" | Out-Null
            if ($lastexitcode = 0) {
               Remove-Item -Path "$AGENT_STATE\$TARGET.installed" -Force | Out-Null
            } else {
                New-Item -Path "$AGENT_STATE\$TARGET.installed" -ItemType "file" -Force | Out-Null
            }
        } else {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   - nothing to check ($TARGET)..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            $PKG_NextStage=$false
        }
    }

    # Package remove
    if ($PKG_uninstall -and $PKG_NextStage) {
        if (-Not $PKG_pin) {
            if (Test-Path "$AGENT_CACHE\$TARGET\run.ps1") {
                if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + uninstalling $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                powershell "$AGENT_CACHE\$TARGET\run.ps1 uninstall" | Out-Null
                Remove-Item -Path "$AGENT_STATE\$TARGET.installed" -Force | Out-Null
            } else {
                if (Test-Path "$AGENT_DATA\debug.txt") {"  W   - nothing to uninstall ($TARGET)..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            $PKG_NextStage=$false
            }
        } else {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + keeping pinned $TARGET installed..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            if ($ACTION -eq 'uninstall') {
                $PKG_NextStage=$false
            }
        }
    }

    # Package clean
    if ($PKG_clean -and $PKG_NextStage) {
        if (-Not $PKG_pin) {
            if (Test-Path "$AGENT_CACHE\$TARGET") {
                if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + cleaning $TARGET..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                Remove-Item -Path "$AGENT_CACHE\$TARGET" -Recurse -Force | Out-Null
                Remove-Item -Path "$AGENT_STATE\$TARGET.cached" -Force | Out-Null
            } else {
                if (Test-Path "$AGENT_DATA\debug.txt") {"  W   - nothing to clean ($TARGET)..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
                $PKG_NextStage=$false
            }
        } else {
            if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + keeping pinned $TARGET in cache..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
            if ($ACTION -eq 'clean') {
                $PKG_NextStage=$false
            }
        }
    } elseif ((-Not $PKG_clean) -and $PKG_NextStage) {
        if (Test-Path "$AGENT_DATA\debug.txt") {"  W   + saving $TARGET in cache..." | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    }

    ################################################

    # Remove temporary package lock
    Remove-Item -Path "$AGENT_STATE\$TARGET.working" -Force | Out-Null

}

###########################################################################################################################################################
###########################################################################################################################################################

### Local queue execution
if ($MODULE -eq 'queue_local') {
    if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"Local queue watcher is NOT allowed to user in DEBUG mode" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        Break
    } else {
        if (Test-Path "$AGENT_DATA\debug.txt") {"M   + Local queue watcher" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    }

	# Endless cycle
	while ($true) {
		agent_queue_local -QUEUE "$AGENT_QUEUE"
		Start-Sleep -s 10
		if (Test-Path "$AGENT_DATA\debug.txt") {"M   + Restarting local queue " | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
	}

################################################

### Remote queue execution
} elseif ($MODULE -eq 'queue_remote') {
    if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"Remote queue watcher is NOT allowed to user in DEBUG mode" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        Break
    } else {
        if (Test-Path "$AGENT_DATA\debug.txt") {"M   + Remote queue watcher" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    }

	# Endless cycle
	while ($true) {
		agent_queue_remote -QUEUE "$SOURCE_QUEUE"
		Start-Sleep -s 10
		if (Test-Path "$AGENT_DATA\debug.txt") {"M   + Restarting remote queue " | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
	}

################################################

### Maintenance task
} elseif ($MODULE -eq 'maintenance') {
    if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"Maintenance task is NOT allowed to user in DEBUG mode, run it via Windows Task Scheduler" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        Break
    } else {
        if (Test-Path "$AGENT_DATA\debug.txt") {"M   + Maintenance task" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    }

    # Create session lock
    if (Test-Path "$AGENT_LOCK_MAINTENANCE") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"  W   ! ERROR: Lockfile exists!" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        Break
    } else {
        New-Item -Path "$AGENT_LOCK_MAINTENANCE" -ItemType "file" -Force | Out-Null
    }
    ################################################

    ## For future use
    agent_check_pinned

    ################################################
    # Remove session lock
    Remove-Item -Path "$AGENT_LOCK_MAINTENANCE" -Force | Out-Null

###########################################################################################################################################################

### Startup and setup
} elseif ($MODULE -eq 'start') {
    if ($env:USERNAME -ne "$env:COMPUTERNAME`$") {
        if (Test-Path "$AGENT_DATA\debug.txt") {"Startup is NOT allowed to user in DEBUG mode" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
        Break
    } else {
        if (Test-Path "$AGENT_DATA\debug.txt") {"M   = Starting up, configuration" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    }

    # Dirs
    if (-not (Test-Path "$AGENT_DATA"))    {New-Item -Path "$AGENT_DATA"    -ItemType directory | Out-Null}
    if (-not (Test-Path "$AGENT_STATE"))   {New-Item -Path "$AGENT_STATE"   -ItemType directory | Out-Null}
    if (-not (Test-Path "$AGENT_CACHE"))   {New-Item -Path "$AGENT_CACHE"   -ItemType directory | Out-Null}

	# Purge lockfiles
	Remove-Item -Path "$AGENT_LOCK_MAINTENANCE" -Force | Out-Null
	
	# Save state
	agent_state_save

	# Background queue tasks start
	Start-Process powershell -Argumentlist "$ThisScriptPath\$ThisScriptName queue_local"
	Start-Process powershell -Argumentlist "$ThisScriptPath\$ThisScriptName queue_remote"

################################################

### Shutdown
} elseif ($MODULE -eq 'stop') {
    if (Test-Path "$AGENT_DATA\debug.txt") {"M   = Shutting down background processes, saving state" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}

	# Background queue tasks kill
	wmic Path win32_process Where "CommandLine Like `'%$ThisScriptName queue%`'" Call Terminate | Out-Null
	
	# Save state
	agent_state_save
	
	# Scheduler tasks stop
	schtasks /end /TN "$DisplayName Maintenance"
	schtasks /end /TN "$DisplayName Startup"
	
###########################################################################################################################################################

### Help =)
} elseif ($MODULE -eq 'help') {
	""
    "$ThisProjectName`. YOU NEED ADMINISTRATIVE RIGHTS TO RUN THIS SCRIPT!"
	""
    " Help:"
    " - You can enable debug mode by creating an empty text file named $AGENT_DATA\debug.txt - this will log messages to $AGENT_DATA\debug.txt. To exit debug mode - remove that file."
	""

###########################################################################################################################################################

} else {
    if (Test-Path "$AGENT_DATA\debug.txt") {"M   ! ERROR: Incorrect action defined!" | Tee-Object -FilePath "$AGENT_DATA\debug.txt" -Append}
    Break
}
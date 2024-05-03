param (
	[Parameter(Mandatory=$true,
	HelpMessage="The name of the platform for which to build content.")]
	[ValidateSet("durango", "pc")]
	[string]$targetPlatform,

	[Parameter(Mandatory=$false,
	HelpMessage="Optional parameters.")]
	[string]$optional,

	[Parameter(Mandatory=$false,
	HelpMessage="False if you want to skip building standalone cache files that are used for ingesting additional tags for mod tools")]
	[string]$buildMapsRelatedToModTools=$true
)

function CheckProcessExit($process, $waitTimeMinutes)
{
	$exitCode = 0

	# If the process hasn't completed after the specified number of minutes, terminate the process and return an error.
	if ($process.WaitForExit($waitTimeMinutes * 60 * 1000))
	{
		$exitCode = $process.ExitCode
	}
	else
	{
		Write-Output "Timed out waiting for process completion"
		$process.CloseMainWindow();
		$exitCode = 1;
	}
	$process.Close();

	if ($exitCode -ne 0)
	{
		exit $exitCode
	}
}

function CheckParallelProcessExit($process, $waitTimeMinutes, $exitCodeHashtable, $operand)
{
	# If the process hasn't completed after the specified number of minutes, terminate the process and return an error.
	$exitCode = 0
	if ($process.WaitForExit($waitTimeMinutes * 60 * 1000))
	{
		$exitCode = $process.ExitCode
	}
	else
	{
		Write-Output "Timed out waiting for $operand"
		$process.CloseMainWindow();
		$exitCode = 1;
	}
	$process.Close();

	# Don't check for failure immediately, but make note of the exit code and allow other parallel jobs to finish.
	# Just bitwise-or the exit code; we don't care what it is, only whether it's nonzero.
	$exitCodeHashtable[0] = $exitCodeHashtable[0] -bor $exitCode

	if ($exitCode -ne 0)
	{
		# We did use Write-Output here, but powershell did not like that when we ended up hitting a non zero exit code
		Write-Host "Failed with exit code $exitCode for $operand"
	}
}

$TOOL_EXE = Join-Path $PsScriptRoot "tool.exe"
$MAP_FILE = Join-Path $PsScriptRoot "AllMaps.txt"
$MAP_LANGUAGES = Join-Path $PsScriptRoot "AllLanguages.txt"
$MAP_CODEX = Join-Path $PsScriptRoot "cache_builder\sounds_file_codex.bin"
$DVD_PROP_LIST = Join-Path $PsScriptRoot "cache_builder\dvd_prop_list.txt"
$MAPS_FOR_MOD_TOOLS_FILE = Join-Path $PsScriptRoot "AllMapsForModTools.txt"

$platformIsDurango = ($targetPlatform -ieq "durango")
$platformIsPC = ($targetPlatform -ieq "pc")
$isDedicatedServer = $optional -like "dedicated-server"

$LANGUAGE = "english"
$VERSION = 0
$SHARED_SOUNDS = "use-shared-sounds"
$DEDICATED_SERVER = $isDedicatedServer ? "dedicated-server" : ""
$USE_FMOD_DATA = $platformIsPc ? "use-fmod-data" : ""

$mapsFolder = $PSScriptRoot;
if ($platformIsPC)
{
	if ($isDedicatedServer)
	{
		$mapsFolder = Join-Path $mapsFolder "maps_dedicated_server"
	}
	else
	{
		$mapsFolder = Join-Path $mapsFolder "maps"
	}
}
elseif($platformIsDurango)
{
	$mapsFolder = Join-Path $mapsFolder "maps_durango"
}

# Multi-socketed systems will report an array of number of logical processors (per socket) instead of an aggregated integral value
$logicalProcessorCount = 0
$logicalProcessorCountValue = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
if ($logicalProcessorCountValue -is [uint])
{
	$logicalProcessorCount = $logicalProcessorCountValue
}
elseif ($logicalProcessorCountValue -is [array])
{
	foreach($processorCount in $logicalProcessorCountValue)
	{
		$logicalProcessorCount += $processorCount
	}
}
else
{
	$logicalProcessorCount = 1
}

# Create a synchronized hashtable to track return codes from parallelized tool jobs
$syncHash = [hashtable]::Synchronized(@{ 0 = 0 })

# Need a way to pass the CheckParallelProcessExit function into the parallel runspace
$CheckParallelProcessExitFunction = Get-Command CheckParallelProcessExit

# Create the cache builder folder if necessary
Write-Output "Create the cache builder folder if necessary"
$cacheBuilderFolder = Join-Path $PSScriptRoot ".\cache_builder"
New-Item -ItemType Directory -Force -Path $cacheBuilderFolder > $null

#1 - Delete everything from cache_builder to avoid stale data corrupting the process
Write-Output "Delete everything from cache_builder to avoid stale data corrupting the process"
Remove-Item -Recurse -Force -Path $cacheBuilderFolder -ErrorAction SilentlyContinue

#2 - Delete maps and RSA manifests from the maps folder
Write-Output "Delete maps and RSA manifests from the maps folder"
Remove-Item -Force -Path (Join-Path $mapsFolder "*.map") -ErrorAction SilentlyContinue
Remove-Item -Force -Path (Join-Path $mapsFolder "security\*.bin") -ErrorAction SilentlyContinue

#3 Build sound index for all maps
Write-Output "Build sound index for all maps"
Measure-Command {

	# ODST does this, but H3 does not. From the looks of the bat's, Reach does not do it either.
	#$process = Start-Process -FilePath $TOOL_EXE -ArgumentList "build-cache-file-cache-sounds-index shared" -PassThru
	#CheckProcessExit $process 30

	$mapFiles = Get-Content -Path $MAP_FILE

	# Can't do this parallel because all maps write to the same sound codex.
	foreach ($mapFile in $mapFiles)
	{
		# Guard against empty lines in the map file list.
		if ($mapFile)
		{
			$append = (Test-Path $MAP_CODEX) ? "append" : ""
			Write-Output "tool build-cache-file-cache-sounds-index $mapFile $append $targetPlatform" | Out-Default
			$process = Start-Process -FilePath $TOOL_EXE -ArgumentList "build-cache-file-cache-sounds-index $mapFile $append $targetPlatform" -PassThru
			CheckProcessExit $process 30
		}
	}
}

#4 Build sound cache files
Write-Output "Build sound cache files"
Measure-Command {
	# PC platforms don't use sound cache files, just need one built to generate the associated tags.
	$languageFiles = $platformIsPC ? $LANGUAGE : (Get-Content -Path $MAP_LANGUAGES)
	$languageFiles | ForEach-Object -ThrottleLimit $logicalProcessorCount -Parallel {
		# Guard against empty lines in the language list
		if ($_)
		{
			$argumentList = "build-cache-file-cache-sounds $using:targetPlatform $_ $using:VERSION $using:USE_FMOD_DATA $using:DEDICATED_SERVER"
			Write-Output $argumentList
			$process = Start-Process -FilePath $using:TOOL_EXE -ArgumentList $argumentList -PassThru
			& $using:CheckParallelProcessExitFunction $process 30 $using:syncHash $_
		}
	} | Out-Default

	if ($syncHash[0] -ne 0)
	{
		exit $syncHash[0]
	}
}

#5 - Generate full shared.map
Write-Output "Generate full shared.map"
Measure-Command {
	$process = Start-Process -FilePath $TOOL_EXE -ArgumentList "build-cache-file-cache-shared-first $targetPlatform $LANGUAGE $VERSION optimizable $SHARED_SOUNDS $USE_FMOD_DATA $DEDICATED_SERVER" -PassThru
	CheckProcessExit $process 30
}

#6 - Generate full campaign.map
Write-Output "Generate full campaign.map"
Measure-Command {
	$process = Start-Process -FilePath $TOOL_EXE -ArgumentList "build-cache-file-cache-campaign-second $targetPlatform $LANGUAGE $VERSION optimizable $USE_FMOD_DATA $DEDICATED_SERVER" -PassThru
	CheckProcessExit $process 30
}

#7 - Generate intermediate files for levels
Write-Output "Generate intermediate files for levels"
Measure-Command {
	$mapFiles = Get-Content -Path $MAP_FILE
	$mapFiles | ForEach-Object -ThrottleLimit $logicalProcessorCount -Parallel {
		# Guard against empty lines in the map file list.
		if ($_)
		{
			$scenarioRelativePath = Join-Path $using:PSScriptRoot "tags\$_.scenario"
			if (Test-Path $scenarioRelativePath)
			{
				$argumentList = "build-cache-file-language-version-optimizable-use-sharing $using:LANGUAGE $using:VERSION $_ $using:targetPlatform $using:SHARED_SOUNDS $using:USE_FMOD_DATA $using:DEDICATED_SERVER"
				Write-Output $argumentList
				$process = Start-Process -FilePath $using:TOOL_EXE -ArgumentList $argumentList -PassThru
				& $using:CheckParallelProcessExitFunction $process 90 $using:syncHash $_
			}
			else
			{
				Write-Output "Missing $scenarioRelativePath"
			}
		}
	} | Out-Default

	if ($syncHash[0] -ne 0)
	{
		exit $syncHash[0]
	}
}

#8 - Create dvd_prop_list.txt
Write-Output "Create prop list"
Measure-Command {
	Remove-Item -Force -Path $DVD_PROP_LIST -ErrorAction SilentlyContinue
	$mapFiles = Get-Content -Path $MAP_FILE
	foreach ($mapFile in $mapFiles)
	{
		# Guard against empty lines in the map file list.
		if ($mapFile)
		{
			$mapName = [System.IO.Path]::GetFileNameWithoutExtension($mapFile)
			Add-Content -Path $DVD_PROP_LIST -Value "..\cache_builder\to_optimize\$mapName.cache_file_resource_gestalt"
		}
	}
}

#9 - Copy shared.map and campaign.map to optimize directory
Write-Output "Copy shared.map and campaign.map to optimize directory"
Measure-Command {
	Remove-Item -Force -Path "cache_builder\to_optimize\shared.map" -ErrorAction SilentlyContinue
	Remove-Item -Force -Path "cache_builder\to_optimize\campaign.map" -ErrorAction SilentlyContinue
	Remove-Item -Force -Path "cache_builder\to_optimize\$LANGUAGE.map" -ErrorAction SilentlyContinue
	Copy-Item -Force -Path (Join-Path $mapsFolder "shared.map") -Destination "cache_builder\to_optimize\shared.map"
	Copy-Item -Force -Path (Join-Path $mapsFolder "campaign.map") -Destination "cache_builder\to_optimize\campaign.map"
	Copy-Item -Force -Path (Join-Path $mapsFolder "$LANGUAGE.map") -Destination "cache_builder\to_optimize\$LANGUAGE.map" -ErrorAction SilentlyContinue
}

#10 - Generate shared intermediate files
Write-Output "Generate shared intermediate files"
Measure-Command {
	$argumentList = "generate-final-shared-layout $DVD_PROP_LIST $targetPlatform $DEDICATED_SERVER"
	$process = Start-Process -FilePath $TOOL_EXE -ArgumentList $argumentList -PassThru
	CheckProcessExit $process 30
}

#11 - Generate optimized level cache files
Write-Output "Generate optimized level cache files"
Measure-Command {
	$mapFiles = Get-Content -Path $MAP_FILE
	$mapFiles | ForEach-Object -ThrottleLimit $logicalProcessorCount -Parallel {
		# Guard against empty lines in the map file list.
		if ($_)
		{
			$scenarioRelativePath = Join-Path $using:PSScriptRoot "tags\$_.scenario"
			if (Test-Path $scenarioRelativePath)
			{
				$argumentList = "build-cache-file-generate-new-layout $_ $using:targetPlatform $using:USE_FMOD_DATA $using:DEDICATED_SERVER"
				Write-Output $argumentList
				$process = Start-Process -FilePath $using:TOOL_EXE -ArgumentList $argumentList -PassThru
				& $using:CheckParallelProcessExitFunction $process 90 $using:syncHash $_
			}
			else
			{
				Write-Output "Missing $scenarioRelativePath"
			}
		}
	} | Out-Default

	if ($syncHash[0] -ne 0)
	{
		exit $syncHash[0]
	}
}

#12 - Generate optimized shared.map
Write-Output "Generate optimized shared.map"
Measure-Command {
	$argumentList = "build-cache-file-link shared $targetPlatform $USE_FMOD_DATA $DEDICATED_SERVER"
	$process = Start-Process -FilePath $TOOL_EXE -ArgumentList $argumentList -PassThru
	CheckProcessExit $process 5
}

#13 - Generate optimized campaign.map
Write-Output "Generate optimized campaign.map"
Measure-Command {
	$argumentList = "build-cache-file-link campaign $targetPlatform $USE_FMOD_DATA $DEDICATED_SERVER"
	$process = Start-Process -FilePath $TOOL_EXE -ArgumentList $argumentList -PassThru
	CheckProcessExit $process 5
}

#14 - Build maps related to mod tools
if ($buildMapsRelatedToModTools -and $platformIsPC)
{
	Write-Output "Build maps related to mod tools"

	$mapFiles = Get-Content -Path $MAPS_FOR_MOD_TOOLS_FILE
	$mapFiles | ForEach-Object -ThrottleLimit $logicalProcessorCount -Parallel {
		# Guard against empty lines in the map file list.
		if ($_ -and !$_.StartsWith(";"))
		{
			$scenarioRelativePath = Join-Path $using:PSScriptRoot "tags\$_.scenario"
			if (Test-Path $scenarioRelativePath)
			{
				$argumentList = "build-cache-file $_ $using:targetPlatform"
				Write-Output $argumentList
				$process = Start-Process -FilePath $using:TOOL_EXE -ArgumentList $argumentList -PassThru
				& $using:CheckParallelProcessExitFunction $process 90 $using:syncHash $_
			}
			else
			{
				Write-Output "Missing $scenarioRelativePath"
			}
		}
	} | Out-Default

	if ($syncHash[0] -ne 0)
	{
		#exit $syncHash[0]
		Write-Output "WARNING: One or more maps for mod tools failed to build"
	}
}

exit 0

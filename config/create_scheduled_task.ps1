param(
    [string]$task_name,
    [string]$task_file_path
)

$task_file = Get-Item $task_file_path -ErrorAction Stop
$task_file_name = $task_file.name
$task_working_directory = $task_file.directory

$task_action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-File ./$task_file_name" -WorkingDirectory "$task_working_directory"
$task_trigger = New-ScheduledTaskTrigger -AtLogon -User "$env:USERNAME"
$task_principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" # -RunLevel Highest
# $task_principal = New-ScheduledTaskPrincipal -UserId "$($env:USERNAME)" -RunLevel 'Highest'
Register-ScheduledTask $task_name -Action $task_action -Trigger $task_trigger -Principal $task_principal
# Set-ScheduledTask -TaskName Task8 -User $env:USERNAME -Password 'Somepass1'
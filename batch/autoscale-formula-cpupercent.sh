// variables
maxNumberOfVMs = 20;
minNumberOfVMs = 2; // $TargetDedicatedNodes
deltaNumberOfVMs = 1;
samplePercentIncreaseThreshold = 0.7;
samplePercentDecreaseThreshold = 0.2;
sampleDuration = TimeInterval_Minute * 3;
// Get the last sample
$sample = (avg($CPUPercent.GetSample(sampleDuration)));
// If the average CPU usage was more than 70%, increase nodes by one, if not true keeps as is
$TargetDedicated = ($sample >= samplePercentIncreaseThreshold ? $TargetDedicatedNodes + deltaNumberOfVMs : $TargetDedicatedNodes);
// If the average CPU usage is below 20% decrease nodes by one, if not true keep as is
$TargetDedicated = ($sample <= samplePercentDecreaseThreshold ? $TargetDedicatedNodes - deltaNumberOfVMs : $TargetDedicated);
// Always keep the number of nodes under the maximum
$TargetDedicated = min($TargetDedicated, maxNumberOfVMs);
// Always keep the number of nodes over the minimum
$TargetDedicated = max($TargetDedicated, minNumberOfVMs);
// Set the new number of nodes
$TargetDedicatedNodes = $TargetDedicated;

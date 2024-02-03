<#
https://platform.openai.com/docs/api-reference/models


response:
{
  "id": "chatcmpl-....",
  "object": "chat.completion",
  "created": 1706976614,
  "model": "gpt-3.5-turbo-0613",
  "choices": [
    {
      "index": 0,
      "message": "@{role=assistant; content=I'm sorry, I am an AI and do not have the capability to know the current time. Please check your device or a reliable source for the accurate time.}",
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 33,
    "total_tokens": 45
  },
  "system_fingerprint": null
}
#>
[cmdletbinding()]
param(
  [string[]]$messages = @(),
  [string]$apiKey = $env:OPENAI_API_KEY, # Replace 'YOUR_API_KEY_HERE' with your OpenAI API key
  [ValidateSet('system', 'user')]
  [string]$messageRole = 'system', # system or user
  [string]$endpoint = 'https://api.openai.com/v1/chat/completions',
  [ValidateSet('gpt-3.5-turbo', 'gpt-3.5-turbo-0613', 'gpt-4-turbo-preview', 'gpt-4')]
  [string]$model = 'gpt-3.5-turbo',
  [string]$logFile = 'c:\temp\openai.log'
)

function main() {
  write-log "===================================="
  write-log ">>>>starting openAI chat request<<<<"
  # Define the API endpoint you want to query

  # Optional: Set headers or other parameters if required
  $headers = @{
    'Authorization' = "Bearer $apiKey"
    'Content-Type'  = 'application/json'
  }
  
  $messageRequests = @()

  foreach ($message in $messages) {
    $messageRequests += @{
      role    = $messageRole
      content = $message
    }
  }

  $requestBody = @{
    model    = $model
    messages = $messageRequests
  }

  # Convert the request body to JSON
  $jsonBody = $requestBody | convertto-json -depth 5
  
  # Make the API request using Invoke-RestMethod
  write-log "$response = invoke-restMethod -Uri $endpoint -Headers $headers -Method Post -Body $jsonBody" -color Cyan
  $response = invoke-restMethod -Uri $endpoint -Headers $headers -Method Post -Body $jsonBody
  #$response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Get

  # Output the response
  write-log ($response | convertto-json -depth 5) -color Magenta
  $global:openaiResponse = $response
  $message = read-messageResponse($response)

  write-log "api response stored in global variable: `$global:openaiResponse" -ForegroundColor Cyan
  if ($logFile) {
    write-log "result appended to logfile: $logFile"
  }

  write-log "response:$($message.content)" -color Green
  write-log ">>>>ending openAI chat request<<<<"
  write-log "===================================="
  return $message.content
}

function read-messageResponse($response) {
  # Extract the response from the API request
  write-log $response
  return $response.choices.message
}

function write-log($message, [switch]$verbose,[ConsoleColor]$color = 'White') {
  $message = "$(get-date) $message"
  if ($logFile) {
    # Write the message to a log file
    $message | out-file -FilePath $logFile -Append
  }

  if ($verbose) {
    write-verbose $message
  }
  else {
    write-host $message -ForegroundColor $color
  }
}

main
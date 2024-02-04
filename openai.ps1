<#
.SYNOPSIS
    This script is a wrapper for the OpenAI API. It sends a message to the API and returns the response.
.DESCRIPTION
    This script is a wrapper for the OpenAI API. It sends a message to the API and returns the response.
    The script requires an API key to be set in the environment variable OPENAI_API_KEY or passed as a parameter.
    The script also requires the message to be sent to the API to be passed as a parameter.
    The script uses the Invoke-RestMethod cmdlet to make the API request.
    The response from the API is then output to the console.
    The script also logs the response to a file if a log file is specified.
.NOTES
    File Name      : openai.ps1
    Author         : Jagilber
    version: 240102

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

.EXAMPLE
    .\openai.ps1 -messages 'can you help me with a question?'
.EXAMPLE
    .\openai.ps1 -messages 'can you help me with a question?' -apiKey '<your-api-key>'
.EXAMPLE
    .\openai.ps1 -messages 'can you help me with a question?' -apiKey '<your-api-key>' -messageRole 'user'
.EXAMPLE
    .\openai.ps1 -messages 'can you help me with a question?' -apiKey '<your-api-key>' -messageRole 'user' -model 'gpt-4'
.PARAMETER messages
    The message to send to the OpenAI API.
.PARAMETER apiKey
    The API key to use for the OpenAI API. If not specified, the script will attempt to use the environment variable OPENAI_API_KEY.
.PARAMETER messageRole
    The role of the message to send to the OpenAI API. This can be either 'system' or 'user'. The default is 'system'.
.PARAMETER model
    The model to use for the OpenAI API. This can be either 'gpt-3.5-turbo', 'gpt-3.5-turbo-0613', 'gpt-4-turbo-preview', or 'gpt-4'. The default is 'gpt-3.5-turbo'.
.PARAMETER logFile
    The log file to write the response from the OpenAI API to. If not specified, the response will not be logged.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/openai.ps1" -outFile "$pwd\openai.ps1";
    write-host 'set api key in environment variable OPENAI_API_KEY or pass as parameter'
    .\openai.ps1 'can you help me with a question?'

#>
[cmdletbinding()]
param(
  [string[]]$messages = @(),
  [string]$apiKey = "$env:OPENAI_API_KEY", # Replace 'YOUR_API_KEY_HERE' with your OpenAI API key
  [ValidateSet('system', 'user')]
  [string]$messageRole = 'user', # system or user
  [string]$endpoint = 'https://api.openai.com/v1/chat/completions',
  [ValidateSet('gpt-3.5-turbo', 'gpt-3.5-turbo-0613', 'gpt-4-turbo-preview', 'gpt-4')]
  [string]$model = 'gpt-3.5-turbo',
  [string]$logFile = 'c:\temp\openai.log'
)

function main() {
  write-log "===================================="
  write-log ">>>>starting openAI chat request<<<<"
  
  if(!$apiKey) {
    write-log "API key not found. Please set the OPENAI_API_KEY environment variable or pass the API key as a parameter." -color Red
    return
  }
  
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

function write-log($message, [switch]$verbose, [ConsoleColor]$color = 'White') {
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
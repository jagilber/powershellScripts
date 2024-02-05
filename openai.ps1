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
    https://platform.openai.com/docs/guides/prompt-engineering
      Tactics:

      Include details in your query to get more relevant answers
      Ask the model to adopt a persona
      Use delimiters to clearly indicate distinct parts of the input
      Specify the steps required to complete a task
      Provide examples
      Specify the desired length of the output

      Instruct the model to answer using a reference text
      Instruct the model to answer with citations from a reference text

      Instruct the model to work out its own solution before rushing to a conclusion
      Use inner monologue or a sequence of queries to hide the model's reasoning process
      Ask the model if it missed anything on previous passes

      When using the OpenAI API chat completion, you can use various message roles to structure the conversation. The choice of roles depends on the context and your specific use case. However, here are ten commonly used message roles:

      1. system: Used for initial instructions or guidance for the assistant.
      2. user: Represents user input, questions, or instructions.
      3. assistant: Represents the assistant's responses or actions.
      4. developer: Used for presenting high-level instructions to the assistant.
      5. customer: Represents a customer or end-user in a customer support scenario.
      6. support: Represents a support agent in a customer support scenario.
      7. manager: Represents a manager or team lead providing instructions or guidance.
      8. reviewer: Used for providing feedback on the assistant's responses or behavior.
      9. colleague: Represents a colleague or team member in a collaboration scenario.
      10. expert: Represents a subject matter expert providing specific domain knowledge.
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
  [ValidateSet('system', 'user', 'assistant', 'developer', 'customer', 'support', 'manager', 'reviewer', 'colleague', 'expert')]
  [string]$messageRole = 'user', # system or user
  [string]$endpoint = 'https://api.openai.com/v1/chat/completions',
  [ValidateSet('gpt-3.5-turbo-1106', 'gpt-4-turbo-preview', 'gpt-4','gpt-3.5-turbo')]
  [string]$model = 'gpt-3.5-turbo-1106',
  [string]$logFile = 'c:\temp\openai.log',
  [int]$seed = $pid,
  [switch]$resetContext,
  [bool]$logProbabilities = $false,
  [string[]]$systemBaseMessages = @(
    'always reply in json format with the response containing complete details',
    'prefer accurate and complete responses including references and citations',
    'use github stackoverflow microsoft and other reliable sources for the response'
  )
)

function main() {
  $startTime = Get-Date
  $messageRequests = @()
  write-log "===================================="
  write-log ">>>>starting openAI chat request $startTime<<<<" -color White
  
  if (!$apiKey) {
    write-log "API key not found. Please set the OPENAI_API_KEY environment variable or pass the API key as a parameter." -color Red
    return
  }
  
  if ($resetContext) {
    write-log "resetting context" -color Yellow
    $global:openaiMessages = @()
  }
  else {
    write-log "using existing context" -color Yellow
  }

  foreach ($message in $systemBaseMessages) {
    $messageRequests += @{
      role    = 'system'
      content = $message
    }
  }

  $global:openaiMessages += $messages

  $headers = @{
    'Authorization' = "Bearer $apiKey"
    'Content-Type'  = 'application/json'
  }

  foreach ($message in $global:openaiMessages) {
    $messageRequests += @{
      role    = $messageRole
      content = $message
    }
  }

  $requestBody = @{
    response_format = @{ 
      type = "json_object"
    }
    model    = $model
    seed     = $seed
    logprobs = $logProbabilities
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
  write-log ">>>>ending openAI chat request $(((get-date) - $startTime).TotalSeconds.ToString("0.0")) seconds<<<<" -color White
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
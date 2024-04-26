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
    version: 240205

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
    .\openai.ps1 -prompts 'can you help me with a question?'
.EXAMPLE
    .\openai.ps1 -prompts 'can you help me with a question?' -apiKey '<your-api-key>'
.EXAMPLE
    .\openai.ps1 -prompts 'can you help me with a question?' -apiKey '<your-api-key>' -promptRole 'user'
.EXAMPLE
    .\openai.ps1 -prompts 'can you help me with a question?' -apiKey '<your-api-key>' -promptRole 'user' -model 'gpt-4'
.PARAMETER prompts
    The message to send to the OpenAI API.
.PARAMETER apiKey
    The API key to use for the OpenAI API. If not specified, the script will attempt to use the environment variable OPENAI_API_KEY.
.PARAMETER promptRole
    The role of the message to send to the OpenAI API. This can be either 'system' or 'user'. The default is 'system'.
.PARAMETER model
    The model to use for the OpenAI API. This can be either 'gpt-3.5-turbo', 'gpt-3.5-turbo-0613', 'gpt-4-turbo', or 'gpt-4'. The default is 'gpt-3.5-turbo'.
.PARAMETER logFile
    The log file to write the response from the OpenAI API to. If not specified, the response will not be logged.
.PARAMETER promptsFile
    The file to store the conversation history. If not specified, the conversation history will not be stored.  
.PARAMETER seed
    The seed to use for the OpenAI API. The default is the process ID of the script.
.PARAMETER newConversation
    If specified, the conversation history will be reset.
.PARAMETER completeConversation
    If specified, the conversation history will not be saved.
.PARAMETER logProbabilities
    If specified, the log probabilities will be included in the response.
.PARAMETER systemPrompts
    The system prompts to use for the OpenAI API. If not specified, the default system prompts will be used.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/openai.ps1" -outFile "$pwd\openai.ps1";
    write-host 'set api key in environment variable OPENAI_API_KEY or pass as parameter'
    .\openai.ps1 'can you help me with a question?'

#>
[cmdletbinding()]
param(
  [string[]]$prompts = @(),
  [string]$apiKey = "$env:OPENAI_API_KEY", 
  [ValidateSet('user', 'system', 'assistant', 'user', 'function', 'tool')]
  [string]$promptRole = 'user', 
  [ValidateSet('https://api.openai.com/v1/chat/completions', 'https://api.openai.com/v1/images/completions', 'https://api.openai.com/v1/davinci-codex/completions')]
  [string]$endpoint = '', #'https://api.openai.com/v1/chat/completions',
  # [ValidateSet('chat', 'images', 'davinci-codex','custom')]
  # [string]$script:endpointType = 'chat',
  [ValidateSet('gpt-3.5-turbo-1106', 'gpt-4-turbo', 'dall-e-2', 'dall-e-3', 'davinci-codex-003')]
  [string]$model = 'gpt-4-turbo',
  [string]$logFile = "$psscriptroot\openai.log",
  [string]$promptsFile = "$psscriptroot\openaiMessages.json",
  [int]$seed = $pid,
  [switch]$newConversation,
  [switch]$completeConversation,
  [bool]$logProbabilities = $false,
  [string]$imageQuality = 'hd',
  [int]$imageCount = 1, # n
  [switch]$imageEdit, # edit image
  [string]$imageFilePng = "$psscriptroot\downloads\openai.png", #"$pwd\openai-$((get-date).tostring('yyMMdd-HHmmss')).png)", # png file to upload and edit . 4mb max with transparency layer and square aspect ratio
  [ValidateSet('256x256', '512x512', '1024x1024', '1792x1024', '1024x1792')]
  [string]$imageSize = '1024x1024', # dall-e 2 only supports up to 512x512
  [ValidateSet('vivid', 'natural')]
  [string]$imageStyle = 'vivid',
  [string]$user = 'default',
  [ValidateSet('url', 'b64_json')]
  [string]$imageResponseFormat = 'url',
  [string[]]$systemPrompts = @(
    'always reply in json format with the response containing complete details',
    'prefer accurate and complete responses including references and citations',
    'use github stackoverflow microsoft wikipedia associated press reuters and other reliable sources for the response'
  ),
  [switch]$whatIf
)

[ValidateSet('chat', 'images', 'davinci-codex', 'custom')]
[string]$script:endpointType = 'chat'
$script:messageRequests = [collections.arraylist]::new()

function main() {
  $startTime = Get-Date
  $messages = @()
  write-log "===================================="
  write-log ">>>>starting openAI chat request $startTime<<<<" -color White
  
  if (!$apiKey) {
    write-log "API key not found. Please set the OPENAI_API_KEY environment variable or pass the API key as a parameter." -color Red
    return
  }

  if($imageFilePng -and !(test-path ([io.path]::GetDirectoryName($imageFilePng)))) {
    write-log "creating directory: [io.path]::GetDirectoryName($imageFilePng)" -color Yellow
    mkdir -Force ([io.path]::GetDirectoryName($imageFilePng))
  }

  $endpoint = get-endpoint #$script:endpointType $endpoint
  
  if ($newConversation -and (Test-Path $promptsFile)) {
    write-log "resetting context" -color Yellow
    write-log "deleting messages file: $promptsFile" -color Yellow
    Remove-Item $promptsFile
  }
  
  if (Test-Path $promptsFile) {
    write-log "reading messages from file: $promptsFile" -color Yellow
    [void]$script:messageRequests.AddRange(@(Get-Content $promptsFile | ConvertFrom-Json))
  }

  $headers = @{
    'Authorization' = "Bearer $apiKey"
    'Content-Type'  = 'application/json'
  }
  if($endpointType -eq 'images') {
    $headers.'Content-Type' = 'multipart/form-data'
    #$headers.Add('Accept', 'image/png')
  }

  $requestBody = build-requestBody $script:messageRequests

  # Convert the request body to JSON
  $jsonBody = $requestBody | convertto-json -depth 5
  
  # Make the API request using Invoke-RestMethod
  write-log "$response = invoke-restMethod -Uri $endpoint -Headers $headers -Method Post -Body $jsonBody" -color Cyan
  if (!$whatIf) {
    $response = invoke-restMethod -Uri $endpoint -Headers $headers -Method Post -Body $jsonBody
  }

  write-log ($response | convertto-json -depth 5) -color Magenta
  $message = read-messageResponse $response $script:messageRequests
  $global:openaiResponse = $response
  write-log "api response stored in global variable: `$global:openaiResponse" -ForegroundColor Cyan

  if ($logFile) {
    write-log "result appended to logfile: $logFile"
  }

  # Write the assistant response to the log file for future reference

  if (!$completeConversation -and $promptsFile) {
    # $script:messageRequests += $message
    $script:messageRequests | ConvertTo-Json | Out-File $promptsFile
    write-log "messages stored in: $promptsFile" -ForegroundColor Cyan  
  }

  write-log "response:$($message.content)" -color Green
  write-log ">>>>ending openAI chat request $(((get-date) - $startTime).TotalSeconds.ToString("0.0")) seconds<<<<" -color White
  write-log "===================================="
  return $message.content
}

function build-requestBody($messageRequests) {
  switch -Wildcard ($script:endpointType) {
    'chat' {
      $requestBody = build-chatRequestBody $messageRequests
    }
    'images' {
      $requestBody = build-imageRequestBody $messageRequests
    }
    'davinci-codex' {
      $requestBody = build-codexRequestBody $messageRequests
    }
  }
  write-log "request body: $($requestBody | convertto-json -depth 5)" -color Yellow
  return $requestBody
}

function build-chatRequestBody($messageRequests) {
  if (!$messageRequests) {
    foreach ($message in $systemPrompts) {
      [void]$messageRequests.Add(@{
          role    = 'system'
          content = $message
        })
    }
  }

  foreach ($message in $prompts) {
    [void]$messageRequests.Add(@{
        role    = $promptRole
        content = $message
      })
  }

  $requestBody = @{
    response_format = @{ 
      type = "json_object"
    }
    model           = $model
    seed            = $seed
    logprobs        = $logProbabilities
    messages        = $messageRequests.toArray()
    user            = $user
  }

  return $requestBody
}

function build-codexRequestBody($messageRequests) {
  throw "model $model not supported"
  $requestBody = @{
    model    = $model
    seed     = $seed
    logprobs = $logProbabilities
    messages = $script:messageRequests.toArray()
    user     = $user
  }

  return $requestBody
}

function build-imageRequestBody($messageRequests) {
  $messageRequests.AddRange($prompts)
  if ($imageEdit) {
    if (!(Test-Path $imageFilePng)) {
      throw "image file not found: $imageFilePng"
    }
    $requestBody = @{
      model           = $model
      prompt          = [string]::join('. ', $messageRequests.ToArray())
      n               = $imageCount
      response_format = $imageResponseFormat
      size            = $imageSize
      user            = $user
      image           = $imageFilePng # to-base64StringFromFile $imageFilePng
    }
  }
  else {
    $requestBody = @{
      model           = $model
      prompt          = [string]::join('. ', $messageRequests.ToArray())
      quality         = $imageQuality
      n               = $imageCount
      response_format = $imageResponseFormat
      size            = $imageSize
      style           = $imageStyle
      user            = $user
    }
  }
  return $requestBody
}

function read-messageResponse($response, [collections.arraylist]$messageRequests) {
  # Extract the response from the API request
  write-log $response

  switch ($script:endpointType) {
    'chat' {
      $message = $response.choices.message
      $messageRequests += $message
      if ($message.content) {
        $error.Clear()
        if (($messageObject = convertfrom-json $message.content) -and !$error) {
          write-log "converting message content from json to compressed json" -color Yellow
          $message.content = ($messageObject | convertto-json -depth 99 -Compress)
        }
      }
    }
    'images' {
      $message = $response.data
      if ($response.data.revised_prompt) {
        write-log "revised prompt: $($response.data.revised_prompt)" -color Yellow
        $messageRequests.Clear()
        $messageRequests.Add($response.data.revised_prompt)
      }
      if($response.data.url) {
        write-log "downloading image: $($response.data.url)" -color Yellow
        write-host "invoke-webRequest -Uri $($response.data.url) -OutFile $imageFilePng"
        invoke-webRequest -Uri $response.data.url -OutFile $imageFilePng
        
        $tempImageFile = $imageFilePng.replace(".png", "$(get-date -f 'yyMMdd-HHmmss').png")
        writ-log "copying image to $tempImageFile" -color Yellow
        copy $imageFilePng $tempImageFile
        code $tempImageFile
      }

      $message | add-member -MemberType NoteProperty -Name 'content' -Value $message.url
    }
    'davinci-codex' {
      throw "model $model not supported"
    }
    default {
      write-log "unknown endpoint type: $script:endpointType" -color Red
    }
  }

  write-log "message: $($message | convertto-json -depth 5)" -color Yellow  
  return $message
}

function to-FileFromBase64String($base64) {
  $bytes = [convert]::FromBase64String($base64)
  $file = [io.path]::GetTempFileName()
  [io.file]::WriteAllBytes($file, $bytes)
  return $file
}

function to-base64StringFromFile($file) {
  $bytes = [io.file]::ReadAllBytes($file)
  $base64 = [convert]::ToBase64String($bytes)
  return $base64 # convertto-json $base64
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

function get-endpoint() {
  #($script:endpointType, $endpoint) {
  switch -Wildcard ($model) {
    'gpt-*' {
      $endpoint = 'https://api.openai.com/v1/chat/completions'
      $script:endpointType = 'chat'
    }
    'dall-e-*' {
      $endpoint = 'https://api.openai.com/v1/images/generations'
      $script:endpointType = 'images'
      if ($imageEdit) {
        $endpoint = 'https://api.openai.com/v1/images/edits'
      }
    }
    'codex-*' {
      $endpoint = 'https://api.openai.com/v1/davinci-codex/completions'
      $script:endpointType = 'davinci-codex'
    }
    default {
      #$endpoint = 'https://api.openai.com/v1/chat/completions'
      $script:endpointType = 'custom'
    }
  }
  write-log "using endpoint: $endpoint" -color Yellow
  return $endpoint
}

main
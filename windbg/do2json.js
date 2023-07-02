/// <reference path="JSProvider.d.ts" /> 
/*
  .load jsprovider.dll
  .scriptload testscript.js
  dx Debugger.State.Scripts.testscript.Contents.ListProcs()
         009d m_BufferOnly              : False (System.Boolean)"
     009e m_Chunked                 : False (System.Boolean)"
     009f m_ChunkEofRecvd           : False (System.Boolean)"
     00a0 FinishedAfterWrite        : False (System.Boolean)"
     00a1 m_IgnoreSocketErrors      : False (System.Boolean)"
     00a2 m_ErrorResponseStatus     : False (System.Boolean)"
   0020 m_ContentLength     : 221 (System.Int64)"
   0028 m_StatusCode        : NotFound (404) (System.Net.HttpStatusCode)"
   002c m_IsVersionHttp11   : True (System.Boolean)"
 0040 m_HttpResponseHeaders       : 000001d61af5d8a0 (System.Net.WebHeaderCollection)"
 0048 m_MediaType                 : NULL"
 0050 m_CharacterSet              : NULL"
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/javascript-debugger-scripting

https://code.visualstudio.com/docs/nodejs/nodejs-debugging
https://ruslan.rocks/posts/how-to-use-jquery-in-javascript-file

https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/-scriptdebug--debug-javascript-
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/-scriptload--load-script-
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/-scriptdebug--debug-javascript-

startup:
(shouldnt be needed)
0:000> .load C:\ScriptProviders\jsprovider.dll
0:000> .scriptload c:\WinDbg\Scripts\arrayVisualizer.js
JavaScript script successfully loaded from 'c:\WinDbg\Scripts\arrayVisualizer.js'
0:000> dx @$myScript = Debugger.State.Scripts.PlayWith64BitValues.Contents


0:000> dx @$myScript = Debugger.State.Scripts.do2json.Contents
dx @$myScript = Debugger.State.Scripts.do2json.Contents                

no command or content
0:000> dx @$myScript = Debugger.State.Scripts.do2json.Contents
@$myScript = Debugger.State.Scripts.do2json.Contents                 : [object Object]
    host             : [object Object]
    parentQueueLevel : 0x0
    parentQueue     
    jsonResultObject : [object Object]

dx @$myScript.parseOutput("0x000001d61af5e430","c:\\temp\\test1.json")

*/

"use strict";

// for testing
//import * as fs from 'fs';

var parentQueueLevel = 0;
var parentQueue = [];
var jsonResultObject = {};
var debug = false;
var isLogOpen = false;
var currentLogFile = '';
var commandResult = null;

function convertToJson(jsonObject, indent = false) {
    var indention = 0;
    if (indent) {
        indention = 2;
    }
    var json = JSON.stringify(jsonObject, null, indention);
    return json;
}

function createJsonObject(match = null) {
    if (!match) {
        match = [0, 0, null, null, null, null, {}];
    }
    var jsonObject = {
        level: match[1].length,
        lastId: match[2],
        name: match[3],
        value: match[4],
        propertyType: match[5],
        attributes: match[6],
        items: {},
        //id: match[3] + '-' + match[1].length + '-' + match[2]
        //parent: null
    };
    return jsonObject;
}

function enableDebug(enable = true) {
    debug = enable;
}

function executeCommand(command) {
    logln(`executing command:${command}`, true);
    commandResult = null;
    if (command) {
        let Control = host.namespace.Debugger.Utility.Control;
        commandResult = Control.ExecuteCommand(command);
    }
    else {
        logln('error:empty command result');
    }

    logln(`commandResult:${commandResult}`, true);
    return commandResult;
}

function getParent() {
    if (parentQueue.length > 0) {
        return parentQueue[parentQueueLevel - 1];
    }
    else {
        logln('error:getParent:parent queue is empty');
        return null;
    }
}

function parseCommandResult(commandResult, regExp) {
    logln(`parseCommandResults:enter:${regExp}`, true);
    var results = [];
    var matchResults = null;
    for (let lineItem of commandResult) {
        logln(`parseCommandResults:checking lineItem:${lineItem}`, true);
        if (matchResults = lineItem.match(regExp)) {
            logln(`parseCommandResults:adding lineItem:${lineItem}`, true);
            results.push(matchResults);
        }
    }
    logln(`parseCommandResults:returning results:${convertToJson(results)}`, true);
    if (!results.length) {
        return null;
    }
    return results;
}

function parseOutputs(command = null, outFile = null, indent = false, content = null) {
    parseOutput(command, outFile, indent, content);
    command = `-static ${command}`;
    outFile = outFile.toLowerCase().replace('.json', '-static.json');
    parseOutput(command, outFile, indent, content);
}

function parseOutput(command = null, outFile = null, indent = false, content = null) {
    var rootPattern = new RegExp(/0x[A-Fa-f0-9]+?\s+(\S+?)$/, 'ig');
    var propertyPattern = new RegExp(/(\s+?)([A-Fa-f0-9]{4})\s(\S+?)\s+?:\s?(.+?)?\s(\(.+?\)|NULL)\S?($|.+$)/); //, 'ig');
    var lineObject = null;
    var currentLineObjectName = null;
    var currentObj = null;
    var currentObjLevel = 0;
    var parentObj = {};
    var commandResult = null;
    var counter = 0;
    var levelSize = 0;
    logln(`parseOutput:enter:command:${command}`);
    if (command) {
        command = `!do2 -c 0 -e 20 -f -vi ${command}`;
        logln(`parseOutput:modified command:${command}`);

        let Control = host.namespace.Debugger.Utility.Control;
        commandResult = Control.ExecuteCommand(command);
    }
    else if (content) {
        commandResult = content.split(/\r?\n/);
    }
    else {
        logln('no command or content');
        return;
    }
    try {
        for (let line of commandResult) {
            //while (counter < commandResult.length) {
            //var line = commandResult[counter++];
            logln(`parsing line:${line}`, true);
            if (!line) { continue };

            var rootMatch = rootPattern.exec(line);
            var propertyMatch = propertyPattern.exec(line);

            if (rootMatch) {
                parentObj = createJsonObject();
                parentObj.name = rootMatch[1];
                jsonResultObject = parentObj;
                currentObj = parentObj.items;
                pushParent(parentObj);
            }
            else if (propertyMatch) {
                lineObject = createJsonObject(propertyMatch);

                if (!lineObject) {
                    logln('error:no line object');
                    continue;
                }

                if (levelSize === 0) { levelSize = lineObject.level; }
                if (currentObjLevel === 0) { currentObjLevel = lineObject.level; }

                // Add child items to parent
                if (currentObjLevel < lineObject.level) {
                    currentObjLevel = lineObject.level;

                    currentObj = currentObj[currentLineObjectName].items = {};
                    parentObj = pushParent(currentObj);
                    currentObj[lineObject.name] = lineObject;
                    currentLineObjectName = lineObject.name;
                    logln('>' + line, true);
                }
                // return to parent
                else if (currentObjLevel > lineObject.level) {
                    for (let i = 0; i < (currentObjLevel - lineObject.level) / levelSize; i++) {
                        parentObj = popParent();
                    }
                    currentObjLevel = lineObject.level;
                    try {
                        currentObj = getParent().items;
                        if (!currentObj) {
                            currentObj = getParent();
                        }
                    }
                    catch (exception) {
                        currentObj = getParent();
                    }

                    currentObj[lineObject.name] = lineObject;
                    currentLineObjectName = lineObject.name;
                    logln('<' + line, true);
                }
                // add to current parent
                else {
                    currentLineObjectName = lineObject.name;
                    currentObj[currentLineObjectName] = lineObject;
                    logln('=' + line, true);
                }
            }
            else {
                logln('no match:' + line);
            }
        }

        logln('writing json', true);
        writeJson(jsonResultObject, outFile, indent);
    }
    catch (e) {
        logln(e);
    }
    finally {
        logln('finished');
    }
}

function logln(e, debugOutput = false) {
    try {
        if (debug || debug === debugOutput) {
            if (String(e).length > 500) {
            // so json does not get truncated and allows for formatting  without \n
            var matches = String(e).match(/.{1,500}(\,|\}|\|\]|$)/g);
            if (matches === null || matches === undefined) {
                host.diagnostics.debugLog(e + '\n');
                return;
            }
            // Use the value
            var tempLine = null;
            for (let line of matches) {
                if (tempLine) {
                    line = tempLine + line;
                    tempLine = null;
                }
                //host.diagnostics.debugLog('debug:' + line.match(/"+/)[0].length + '\n');
                if (line === null || line === undefined) {
                    host.diagnostics.debugLog('ERROR:line null');
                    continue;
                }

                var lineMatches = line.match(/"/g);
                if (lineMatches === null || lineMatches === undefined) {
                    host.diagnostics.debugLog('ERROR:line matches null');
                    continue;
                }
                
                if (lineMatches.length % 2) {
                    host.diagnostics.debugLog(`ERROR:${lineMatches.length} is odd\n${line}`);
                    tempLine = line;
                    continue;
                }
                host.diagnostics.debugLog(line + '\n');
                tempLine = null;
            }
            }
            else {
                host.diagnostics.debugLog(e + '\n');
            }
        }
    }
    catch (exception) {
        try {
            host.diagnostics.debugLog(`exception:${exception}\n`);
            host.diagnostics.debugLog(e + '\n');
        }
        catch (exception) {
            console.log(e + '\n');
        }
        
    }
}

function logClose() {
    if (logState().isLogOpen) {
        logln(`closing open log file:${logState.currentLogFile}`, true);
        executeCommand('.logClose');
    }
    else {
        logln('log file already closed.', true);
    }
}

function logOpen(logFile) {
    if (!logState().isLogOpen) {
        logln(`opening log file:${logFile}`, true);
        executeCommand(`.logOpen ${logFile}`);
    }
    else {
        logln('log file already open.', true);
    }
}

function logState() {
    var logResult = executeCommand('.logFile');
    var logFileOpen = false;
    var logMatch = parseCommandResult(logResult, /No log file open/i);
    if (!logMatch) {
        logMatch = parseCommandResult(logResult, /Log '(.+?)' (.*)$/i);
        logFileOpen = logMatch[0][2].toLowerCase() === 'open';
    }

    var logInfo = {
        currentLogFile: logMatch[0][1],
        isLogOpen: logFileOpen
    }
    currentLogFile = logInfo.currentLogFile;
    isLogOpen = logInfo.isLogOpen;
    logln(`logState:returning:${convertToJson(logInfo)}`, true);
    return logInfo;
}

function popParent() {
    var parentObj = null;
    if (parentQueue.length > 0) {
        parentQueue.pop();
        parentObj = parentQueue[--parentQueueLevel - 1];
        logln('popped parentqueue. queue size:' + parentQueueLevel, true);
    }
    else {
        logln('error:popParent:parent queue is empty');
    }
    return parentObj;
}

function pushParent(parentObj) {
    if (!parentObj) {
        return;
    }

    parentQueue.push(parentObj);
    parentQueueLevel++;

    logln('pushed parentqueue. queue size:' + parentQueueLevel, true);
    return parentObj;
}

function readFile(file) {
    throw 'not implemented';
    // const fs = require('fs')
    // var content = fs.readFileSync(file, 'utf8');
    // return content;
}

function writeFile(file, content) {
    logln(`writing file:${file}`);
    // try {
    //fs.writeFileSync(file, content);
    // }
    // catch (e) {
    logOpen(file);
    logln(content);
    logClose();
    // }
}

function writeJson(jsonObject, outFile = null, indent = false) {
    logln(`writing json:${outFile}`, true);
    var json = convertToJson(jsonObject, indent);
    if (outFile) {
        writeFile(outFile, json);
    }
    else {
        logln(json);
    }
}

function debugTest(inputFile = null, outputFile = null) {
    const fs = require('fs');
    var testContent = readFile(inputFile);
    parseOutput(null, outputFile, true, testContent);
}

function initializeScript() {
    // Add code here that you want to run every time the script is loaded. 
    // We will just send a message to indicate that function was called.
    logln("***> initializeScript was called\n");
}

function invokeScript() {
    logState();
}

// test
//parseOutput('!do2 -c 0 -e 20 -f -vi 0x000001d61af5e430');
//initializeScript();
//invokeScript();
//debugTest('c:\\temp\\test1-static.json');


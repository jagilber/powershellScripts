//// <reference path="JSProvider.d.ts" /> 
/*
calls  mex  do2 -c 0 -e 20 -f -vi <address>
parses output and creates json file

example do2 output:
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

reference:
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/javascript-debugger-scripting

startup:
(shouldnt be needed)
0:000> .load C:\ScriptProviders\jsprovider.dll
0:000> .scriptload c:\WinDbg\Scripts\do2json.js


0:000> dx @$myScript = Debugger.State.Scripts.do2json.Contents
dx @$myScript = Debugger.State.Scripts.do2json.Contents

0:000> dx @$myScript = Debugger.State.Scripts.do2json.Contents
@$myScript = Debugger.State.Scripts.do2json.Contents                 : [object Object]
    host             : [object Object]
    parentQueueLevel : 0x0
    parentQueue
    jsonResultObject : [object Object]

example usage
dx @$myScript.do2json("0x000001d61af5e430","c:\\temp\\test1.json")
dx @$myScript.do2json("0x000001d61af5e430","c:\\temp\\test1.json", true)

*/
"use strict";
var parentQueueLevel = 0;
var parentQueue = [];
var jsonResultObject = {};
var debug = false;
var isLogOpen = false;
var currentLogFile = '';
var commandResult = null;
var depth = 20;
var resultCount = 0; // unlimited
var do2command = "!do2 -c " + resultCount + " -e " + depth + " -f -vi";
function logln(data, debugOutput) {
    if (debugOutput === void 0) { debugOutput = false; }
    try {
        if (debug || debug === debugOutput) {
            if (String(data).length > 500) {
                // so json does not get truncated and allows for formatting  without \n
                var matches = String(data).match(/(\{|\}|\[|\])\,?\s*?$|.{1,500}(\,|\}|\]|$)/g);
                if (matches === null || matches === undefined) {
                    if (debug) {
                        host.diagnostics.debugLog('ERROR:matches null\n');
                    }
                    host.diagnostics.debugLog(data + '\n');
                    return;
                }
                // Use the value
                var tempLine = null;
                for (var _i = 0, matches_1 = matches; _i < matches_1.length; _i++) {
                    var line = matches_1[_i];
                    if (tempLine) {
                        line = tempLine + line;
                        tempLine = null;
                    }
                    //host.diagnostics.debugLog('debug:' + line.match(/"+/)[0].length + '\n');
                    if (line === null || line === undefined) {
                        if (debug) {
                            host.diagnostics.debugLog('ERROR:line null\n');
                        }
                        continue;
                    }
                    // check  for odd number of quotes indicating an incomplete string.
                    // keep string and cocatenate.
                    var lineMatches = line.match(/\"/g);
                    if (lineMatches === null || lineMatches === undefined) {
                        //host.diagnostics.debugLog(`ERROR:line matches null\n${line}\n`);
                        host.diagnostics.debugLog(line + '\n');
                        continue;
                    }
                    if (lineMatches.length % 2) {
                        if (debug) {
                            host.diagnostics.debugLog("ERROR:" + lineMatches.length + " line has odd number of quotes. appending:" + line + "\n");
                        }
                        tempLine = line;
                        continue;
                    }
                    host.diagnostics.debugLog(line + '\n');
                    tempLine = null;
                }
            }
            else {
                host.diagnostics.debugLog(data + '\n');
            }
        }
    }
    catch (exception) {
        try {
            host.diagnostics.debugLog("exception:" + exception + "\n");
            host.diagnostics.debugLog(data + '\n');
        }
        catch (exception) {
            console.log(data + '\n');
        }
    }
}
function createFile(fileName) {
    logln("creating file:" + fileName);
    var newFile = null;
    try {
        var fileSystem = host.namespace.Debugger.Utility.FileSystem;
        newFile = fileSystem.CreateFile(fileName, disposition.CreateAlways.toString());
        return newFile;
    }
    catch (e) {
        logln("error:creating file:" + fileName + "\n" + e);
        if (newFile) {
            newFile.Close();
        }
        return null;
    }
}
function convertToJson(jsonObject, indent) {
    if (indent === void 0) { indent = false; }
    var indention = 0;
    if (indent) {
        indention = 2;
    }
    var json = JSON.stringify(jsonObject, null, indention);
    return json;
}
function createJsonObject(match) {
    if (match === void 0) { match = null; }
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
    };
    return jsonObject;
}
function debugTest(inputFile, outputFile) {
    //const fs = require('fs');
    var testContent = readFile(inputFile);
    do2json(null, outputFile, true, testContent);
}
function executeCommand(command) {
    if (command === void 0) { command = null; }
    logln("executing command:" + command, true);
    var commandResult = null;
    if (command) {
        var control = host.namespace.Debugger.Utility.Control;
        commandResult = control.ExecuteCommand(command);
    }
    else {
        logln('error:empty command result');
    }
    logln("commandResult:" + commandResult, true);
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
function do2jsons(command, outFile, indent, content) {
    if (command === void 0) { command = null; }
    if (outFile === void 0) { outFile = null; }
    if (indent === void 0) { indent = false; }
    if (content === void 0) { content = null; }
    do2json(command, outFile, indent, content);
    command = "-static " + command;
    if (outFile !== null) {
        outFile = outFile.toLowerCase().replace('.json', '-static.json');
    }
    do2json(command, outFile, indent, content);
}
function do2json(command, outFile, indent, content) {
    if (command === void 0) { command = null; }
    if (outFile === void 0) { outFile = null; }
    if (indent === void 0) { indent = false; }
    if (content === void 0) { content = null; }
    var rootPattern = /0x[A-Fa-f0-9]+?\s+(\S+?)$/ig;
    var propertyPattern = /(\s+?)([A-Fa-f0-9]{4})\s(\S+?)\s+?:\s?(.+?)?\s(\(.+?\)|NULL)\S?($|.+$)/;
    var lineObject = null;
    var currentLineObjectName = undefined;
    var currentObj = undefined;
    var currentObjLevel = 0;
    var parentObj = {};
    var commandResult = null;
    var levelSize = 0;
    initializeVariables();
    logln("parseOutput:enter:command:" + command);
    if (command) {
        command = do2command + " " + command;
        logln("parseOutput:modified command:" + command);
        var control = host.namespace.Debugger.Utility.Control;
        commandResult = control.ExecuteCommand(command);
    }
    else if (content) {
        commandResult = content.split(/\r?\n/);
    }
    else {
        logln('no command or content');
        return;
    }
    try {
        if (!commandResult) {
            logln('no command result');
            return;
        }
        for (var _i = 0, commandResult_1 = commandResult; _i < commandResult_1.length; _i++) {
            var line = commandResult_1[_i];
            logln("parsing line:" + line, true);
            if (!line) {
                continue;
            }
            ;
            var rootMatch = rootPattern.exec(line);
            var propertyMatch = propertyPattern.exec(line);
            if (rootMatch) {
                parentObj = createJsonObject();
                parentObj.name = rootMatch[1];
                jsonResultObject = parentObj;
                currentObj = parentObj.items;
                pushParent(parentObj);
            }
            else if (propertyMatch !== null) {
                lineObject = createJsonObject(propertyMatch);
                if (!lineObject) {
                    logln('error:no line object');
                    continue;
                }
                if (levelSize === 0) {
                    levelSize = lineObject.level;
                }
                if (currentObjLevel === 0) {
                    currentObjLevel = lineObject.level;
                }
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
                    for (var i = 0; i < (currentObjLevel - lineObject.level) / levelSize; i++) {
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
function initializeVariables() {
    parentQueueLevel = 0;
    parentQueue = [];
    jsonResultObject = {};
    //debug = false;
    //isLogOpen = false;
    //currentLogFile = '';
    commandResult = null;
    //depth = 20;
    //resultCount = 0; // unlimited
    do2command = "!do2 -c " + resultCount + " -e " + depth + " -f -vi";
}
function logClose() {
    if (isLogOpen) {
        //@ts-ignore TS2339
        logln("closing open log file:" + logState.currentLogFile, true);
        executeCommand('.logClose');
        isLogOpen = false;
        currentLogFile = '';
    }
    else {
        logln('log file already closed.', true);
    }
}
function logOpen(logFile) {
    if (!isLogOpen) {
        logln("opening log file:" + logFile, true);
        executeCommand(".logOpen " + logFile);
        isLogOpen = true;
        currentLogFile = logFile;
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
        if (logMatch) {
            logFileOpen = logMatch[0][2].toLowerCase() === 'open';
        }
        else {
            return null;
        }
        //logFileOpen = logMatch[0][2].toLowerCase() === 'open';
    }
    var logInfo = {
        currentLogFile: logMatch[0][1],
        isLogOpen: logFileOpen
    };
    currentLogFile = logInfo.currentLogFile;
    isLogOpen = logInfo.isLogOpen;
    logln("logState:returning:" + convertToJson(logInfo), true);
    return logInfo;
}
function parseCommandResult(commandResult, regExp) {
    logln("parseCommandResults:enter:" + regExp, true);
    var results = [];
    var matchResults = null;
    if (!commandResult) {
        logln("parseCommandResults:commandResult is null", true);
        return null;
    }
    for (var _i = 0, commandResult_2 = commandResult; _i < commandResult_2.length; _i++) {
        var lineItem = commandResult_2[_i];
        logln("parseCommandResults:checking lineItem:" + lineItem, true);
        if (matchResults = lineItem.match(regExp)) {
            logln("parseCommandResults:adding lineItem:" + lineItem, true);
            results.push(matchResults);
        }
    }
    logln("parseCommandResults:returning results:" + convertToJson(results), true);
    if (!results.length) {
        return null;
    }
    return results;
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
function readFile(fileName) {
    logln("reading file:" + fileName);
    var currentFile = null;
    try {
        var fileSystem = host.namespace.Debugger.Utility.FileSystem;
        currentFile = fileSystem.OpenFile(fileName);
        var reader = fileSystem.CreateTextReader(currentFile, encoding.Utf8.toString());
        var content = reader.ReadLineContents();
        currentFile.Close();
        return content;
    }
    catch (e) {
        var exStr = "error:reading file:" + fileName + "\n" + e;
        logln(exStr);
        throw exStr;
    }
    finally {
        if (currentFile) {
            currentFile.Close();
        }
    }
}
function setDebug(enable) {
    if (enable === void 0) { enable = true; }
    debug = enable;
}
function setDepth(level) {
    if (level === void 0) { level = 20; }
    depth = level;
}
function setResultCount(count) {
    if (count === void 0) { count = 0; }
    resultCount = count;
}
function writeFile(fileName, content) {
    logln("writing file:" + fileName);
    // uncomment below to debug
    // const fs = require('fs')
    var newFile = null;
    try {
        //      fs.writeFileSync(file, content);
        var fileSystem = host.namespace.Debugger.Utility.FileSystem;
        if (fileSystem.FileExists(fileName)) {
            logln("deleting file:" + fileName);
            fileSystem.DeleteFile(fileName);
        }
        newFile = createFile(fileName);
        if (!newFile) {
            throw "error:creating file:" + fileName;
        }
        var writer = fileSystem.CreateTextWriter(newFile, encoding.Utf8.toString());
        writer.Write(content);
        newFile.Close();
        logln("file: " + fileName + " written successfully.\n" + content, true);
    }
    catch (e) {
        var exStr = "error:writing file:" + fileName + "\n" + e;
        logln(exStr);
        logOpen(fileName);
        logln(content);
        logClose();
        throw exStr;
    }
    finally {
        if (newFile) {
            newFile.Close();
        }
    }
}
function writeJson(jsonObject, outFile, indent) {
    if (outFile === void 0) { outFile = null; }
    if (indent === void 0) { indent = false; }
    logln("writing json:" + outFile, true);
    var json = convertToJson(jsonObject, indent);
    if (outFile) {
        writeFile(outFile, json);
    }
    else {
        logln(json);
    }
}
function initializeScript() {
    // called when the script is loaded by windbg
    // Add code here that you want to run every time the script is loaded. 
    // We will just send a message to indicate that function was called.
    logln("***> initializeScript was called\n");
    initializeVariables();
}
function invokeScript() {
    // called when the script is invoked by windbg
    logState();
}

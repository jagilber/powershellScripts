﻿//// <reference path="JSProvider.d.ts" />
/*
calls  mex  !do2 -c 0 -e 20 -f -vi <address>
parses output and creates json file

reference:
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/javascript-debugger-scripting
https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/-scriptdebug--debug-javascript-

startup debug commands:
node .\do2jsondev.js
tsc --b --watch
(shouldnt be needed)
.load jsprovider.dll;
.scriptlist;
.scriptload I:\githubshared\jagilber\powershellScripts\windbg\do2jsondev.js;
.scriptdebug I:\githubshared\jagilber\powershellScripts\windbg\do2jsondev.js;
sxe en;
bp 0:0;
q;
# use below to load all js content
dx @$scriptContents.set("debug",true)
dx @$scriptContents.set("do2command","k")
dx @$scriptContents.do2json(" ")
# should breakin

startup commands:
.scriptlist
.scriptload I:\githubshared\jagilber\powershellScripts\windbg\do2json.js
.scriptrun I:\githubshared\jagilber\powershellScripts\windbg\do2json.js

dx @$myScript = Debugger.State.Scripts.do2json.Contents
dx @$myScript.do2json("0x000001d61af5e430","c:\\temp\\test.json",true)
or
dx @$scriptContents.do2json("0x000001d61af5e430","c:\\temp\\test.json",true)

*/

"use strict";

var parentQueueLevel: number = 0;
var parentQueue: any[] = [];
var jsonResultObject: any = {};
var debug: boolean = false;
var isLogOpen: boolean = false;
var currentLogFile: string | undefined = '';
var commandResult: string[] | null = null;
var depth: number = 20;
var resultCount: number = 0; // unlimited
var do2command: string = `!do2 -c ${resultCount} -e ${depth} -f -vi`;

function logln(data: any | null, debugOutput: boolean = false) {
    //host.diagnostics.debugLog('test::' + data + '\n');
    try {
        if (debug || debug === debugOutput) {
            if (String(data).length > 500) {
                // so json does not get truncated and allows for formatting  without \n
                var matches: string[] | null = String(data).match(/(\{|\}|\[|\])\,?\s*?$|.{1,500}(\,|\}|\]|$)/g);
                if (matches === null || matches === undefined) {
                    if (debug) {
                        host.diagnostics.debugLog('ERROR:matches null\n');
                    }
                    host.diagnostics.debugLog(data + '\n');
                    return;
                }
                // Use the value
                var tempLine: string | null = null;
                for (let line of matches) {
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
                    var lineMatches: string[] | null = line.match(/\"/g);
                    if (lineMatches === null || lineMatches === undefined) {
                        //host.diagnostics.debugLog(`ERROR:line matches null\n${line}\n`);
                        host.diagnostics.debugLog(line + '\n');
                        continue;
                    }

                    if (lineMatches.length % 2) {
                        if (debug) {
                            host.diagnostics.debugLog(`ERROR:${lineMatches.length} line has odd number of quotes. appending:${line}\n`);
                        }
                        tempLine = line;
                        continue;
                    }
                    host.diagnostics.debugLog(line + '\n');
                    tempLine = null;
                }
            }
        }
        else {
            host.diagnostics.debugLog(data + '\n');
        }
    }
    catch (exception) {
        try {
            host.diagnostics.debugLog(`exception:${exception}\n`);
            host.diagnostics.debugLog(data + '\n');
        }
        catch (exception) {
            console.log(data + '\n');
        }
    }
}

function createFile(fileName: string) {
    logln(`creating file:${fileName}`);
    var newFile: file | null = null;
    try {

        let fileSystem: typeof host.namespace.Debugger.Utility.FileSystem = host.namespace.Debugger.Utility.FileSystem;
        newFile = fileSystem.CreateFile(fileName, disposition.CreateAlways);
        return newFile;
    }
    catch (e) {
        logln(`error:creating file:${fileName}\n${e}`);
        if (newFile) {
            newFile.Close();
        }

        return null;
    }
}

function convertToJson(jsonObject: any, indent: boolean = false) {
    var indention: number = 0;
    if (indent) {
        indention = 2;
    }
    var json: string | null = JSON.stringify(jsonObject, null, indention);
    return json;
}

function createJsonObject(match: any[] | null = null) {
    if (!match) {
        match = [0, 0, null, null, null, null, {}];
    }
    var jsonObject: any = {
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

function debugTest(inputFile: string, outputFile: string) {
    //const fs = require('fs');
    var testContent = readFile(inputFile);
    do2json(null, outputFile, true, testContent);
}

function executeCommand(command: string | null = null) {
    logln(`executing command:${command}`, true);
    var commandResults: string[] = [];
    var commandResult: any = undefined; //: any = null;

    if (command) {

        let control: typeof host.namespace.Debugger.Utility.Control = host.namespace.Debugger.Utility.Control;
        commandResult = control.ExecuteCommand(command);
    }
    else {
        logln('error:empty command');
    }

    if (!commandResult) {
        logln('error:commandResult is null');
        return null;
    }
    else {
        logln(`commandResult:${convertToJson(commandResult)}`, true);
    }

    logln(`commandResults:`, true);

    for (let line of commandResult) {
        logln(line, true);
        commandResults.push(line);
    }

    return commandResults;
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


function do2jsons(command: string | null = null, outFile: string | null = null, indent: boolean = false, content: string | null = null) {
    do2json(command, outFile, indent, content);
    command = `-static ${command}`;

    if (outFile !== null) {
        outFile = outFile.toLowerCase().replace('.json', '-static.json');
    }

    do2json(command, outFile, indent, content);
}

function do2json(command: string | null = null, outFile: string | null = null, indent: boolean = false, content: string | null = null) {
    var rootPattern = /0x[A-Fa-f0-9]+?\s+(\S+?)$/ig;
    var propertyPattern = /(\s+?)([A-Fa-f0-9]{4})\s(\S+?)\s+?:\s?(.+?)?\s(\(.+?\)|NULL)\S?($|.+$)/;
    var lineObject: any | null = null;
    var currentLineObjectName: any = undefined;
    var currentObj: any = undefined;
    var currentObjLevel: number = 0;
    var parentObj: any = {};
    var commandResult: string[] | null = null;
    var levelSize: number = 0;

    initializeVariables();
    logln(`parseOutput:enter:command:${command}`);

    if (command) {
        command = `${do2command} ${command}`;
        logln(`parseOutput:modified command:${command}`);

        commandResult = executeCommand(command);
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

        for (let line of commandResult) {
            logln(`parsing line:${line}`, true);
            if (!line) { continue };
            var rootMatch: string[] | null = rootPattern.exec(line);
            var propertyMatch: string[] | null = propertyPattern.exec(line);

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
    //do2command = `!do2 -c ${resultCount} -e ${depth} -f -vi`;
}

function logClose() {
    if (isLogOpen) {
        //@ts-ignore TS2339
        logln(`closing open log file:${logState.currentLogFile}`, true);
        void executeCommand('.logClose');
        isLogOpen = false;
        currentLogFile = '';
    }
    else {
        logln('log file already closed.', true);
    }
}

function logOpen(logFile: string) {
    if (!isLogOpen) {
        logln(`opening log file:${logFile}`, true);
        void executeCommand(`.logOpen ${logFile}`);
        isLogOpen = true;
        currentLogFile = logFile;
    }
    else {
        logln('log file already open.', true);
    }
}

function logState() {
    var logResult: string[] | null = executeCommand('.logFile');
    var logFileOpen: boolean | null = false;
    var logMatch: string[] | null = parseCommandResult(logResult, /No log file open/i);
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
    }
    currentLogFile = logInfo.currentLogFile;
    isLogOpen = logInfo.isLogOpen;
    logln(`logState:returning:${convertToJson(logInfo)}`, true);
    return logInfo;
}

function parseCommandResult(commandResult: string[] | null, regExp: RegExp) {
    logln(`parseCommandResults:enter:${regExp}`, true);
    var results: string[] | null = [];
    var matchResults: any | null = null;
    if (!commandResult) {
        logln(`parseCommandResults:commandResult is null`, true);
        return null;
    }
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

function popParent() {
    var parentObj: any = null;
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

function pushParent(parentObj: any) {
    if (!parentObj) {
        return;
    }

    parentQueue.push(parentObj);
    parentQueueLevel++;

    logln('pushed parentqueue. queue size:' + parentQueueLevel, true);
    return parentObj;
}

function readFile(fileName: string) {
    logln(`reading file:${fileName}`);
    var currentFile: file | null = null;
    try {

        let fileSystem: typeof host.namespace.Debugger.Utility.FileSystem = host.namespace.Debugger.Utility.FileSystem;
        currentFile = fileSystem.OpenFile(fileName);
        var reader: textReader = fileSystem.CreateTextReader(currentFile, encoding.Utf8);
        var content: any = reader.ReadLineContents();
        currentFile.Close();
        return content;
    }
    catch (e) {
        var exStr: string = `error:reading file:${fileName}\n${e}`;
        logln(exStr);
        throw exStr;
    }
    finally {
        if (currentFile) {
            currentFile.Close();
        }
    }

}

function set(name: string, value: object) {
    if (name === 'debug') {
        setDebug(<boolean><unknown>value);
    }
    else if (name === 'depth') {
        setDepth(<number><unknown>value);
    }
    else if (name === 'resultCount') {
        setResultCount(<number><unknown>value);
    }
    else if (name === 'do2command') {
        setCommand(<string><unknown>value);
    }
    else {
        logln(`error:set:unknown name:${name}`);
    }
}

function setCommand(command: string) {
    do2command = command;
}

function setDebug(enable: boolean = true) {
    debug = enable;
}

function setDepth(level: number = 20) {
    depth = level;
}

function setResultCount(count: number = 0) {
    resultCount = count;
}

function writeFile(fileName: string, content: string) {
    logln(`writing file:${fileName}`);
    // uncomment below to debug
    // const fs = require('fs')
    var newFile: file | null = null;
    try {
        //      fs.writeFileSync(file, content);
        let fileSystem: any = host.namespace.Debugger.Utility.FileSystem;

        if (fileSystem.FileExists(fileName)) {
            logln(`deleting file:${fileName}`);
            fileSystem.DeleteFile(fileName);
        }

        newFile = createFile(fileName);
        if (!newFile) { throw `error:creating file:${fileName}`; }

        var writer: textWriter = fileSystem.CreateTextWriter(newFile, encoding.Utf8);
        writer.Write(content);
        newFile.Close();
        logln(`file: ${fileName} written successfully.\n${content}`, true)
    }
    catch (e) {
        var exStr: string = `error:writing file:${fileName}\n${e}`;
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

function writeJson(jsonObject: any, outFile: string | null = null, indent: boolean = false) {
    logln(`writing json:${outFile}`, true);
    var json: string = convertToJson(jsonObject, indent);
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

// test
//do2json('0x000001d61af5e430');
//debugTest('c:\\temp\\test1-static.json');


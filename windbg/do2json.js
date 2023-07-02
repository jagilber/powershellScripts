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
@$myScript = Debugger.State.Scripts.do2json.Contents                


*/

"use strict";

// for testing
//import * as fs from 'fs';

var parentQueueLevel = 0;
var parentQueue = [];
var jsonResultObject = {};

function convertToJson(jsonObject) {
    var json = JSON.stringify(jsonObject, null, 2);
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

function getParent() {
    if (parentQueue.length > 0) {
        return parentQueue[parentQueueLevel - 1];
    }
    else {
        logln('error:getParent:parent queue is empty');
        return null;
    }
}

function invokeScript(command = null, content = null, outFile = null) {
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

    if (command) {
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
        //for (let line of commandResult) {
        while (counter < commandResult.length) {
            var line = commandResult[counter++];

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
                    logln('>' + line);
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
                    logln('<' + line);
                }
                // add to current parent
                else {
                    currentLineObjectName = lineObject.name;
                    currentObj[currentLineObjectName] = lineObject;
                    logln('=' + line);
                }
            }
            else {
                logln('no match:' + line);
            }
        }

        writeJson(jsonResultObject);
    }
    catch (e) {
        logln(e);
    }
    finally {
        writeFile(outFile, convertToJson(jsonResultObject));
    }
}

function logln(e) {
    try {
        //writeFile(logFile, e + '\n');
        //writeFile(outFile, convertToJson(jsonResultObject));
        host.diagnostics.debugLog(e + '\n');
    }
    catch (exception) {
        console.log(e);
    }
}

function popParent() {
    var parentObj = null;
    if (parentQueue.length > 0) {
        parentQueue.pop();
        parentObj = parentQueue[--parentQueueLevel - 1];
        logln('popped parentqueue. queue size:' + parentQueueLevel);
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

    logln('pushed parentqueue. queue size:' + parentQueueLevel);
    return parentObj;
}

function readFile(file) {
    //const fs = require('fs')
    throw 'not implemented';
    //var content = fs.readFileSync(file, 'utf8');
    //return content;
}

function writeFile(file, content) {
    try {
        fs.writeFileSync(file, content);
    }
    catch (e) {
        logln(e);
    }
}

function writeJson(jsonObject) {
    var json = convertToJson(jsonObject);
    logln(json);
}

function initializeScript()
{
    // Add code here that you want to run every time the script is loaded. 
    // We will just send a message to indicate that function was called.
    logln("***> initializeScript was called\n");
}


// test
//invokeScript('!do2 -c 0 -e 20 -f -vi 0x000001d61af5e430');
//invokeScript();

// Copyright (c) 2022, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/log;
import ballerinax/googleapis.drive;
import ballerina/task;
import ballerina/time;

# Drive event listener   
@display {label: "Google Drive", iconPath: "docs/icon.png"}
public class Listener {
    # Watch Channel ID
    public string channelUuid = EMPTY_STRING;
    # Watch Resource ID
    public string watchResourceId = EMPTY_STRING;
    private string currentToken = EMPTY_STRING;
    private string specificFolderOrFileId = EMPTY_STRING;
    private drive:Client driveClient;
    private boolean isWatchOnSpecificResource = false;
    private boolean isFolder = true;
    private ListenerConfiguration config;
    private http:Listener httpListener;
    private string domainVerificationFileContent;
    private DispatcherService dispatcherService;
    private drive:ConnectionConfig driveConnection;
    # Initializes Google Drive connector listener.
    #
    # + config - Listener configuration
    # + return - An error on failure of initialization or else `()`
    public isolated function init(ListenerConfiguration config, int|http:Listener listenOn = 8090) returns @tainted error? {
        if listenOn is http:Listener {
            self.httpListener = listenOn;
        } else {
            self.httpListener = check new (listenOn);
        }
        self.driveConnection = {
            auth: {
                clientId: config.clientId,
                clientSecret: config.clientSecret,
                refreshUrl: config.refreshUrl,
                refreshToken: config.refreshToken
            }
        };
        self.driveClient = check new (self.driveConnection);
        self.config = config;
        self.domainVerificationFileContent = config.domainVerificationFileContent;
        self.dispatcherService = new (config, self.channelUuid, self.currentToken, self.watchResourceId,
                                            self.isWatchOnSpecificResource, self.isFolder,
                                            self.specificFolderOrFileId, self.domainVerificationFileContent, self.driveConnection);
    }

    public isolated function attach(GenericServiceType serviceRef, () attachPoint) returns error? {
        string serviceTypeStr = self.getServiceTypeStr(serviceRef);
        check self.dispatcherService.addServiceRef(serviceTypeStr, serviceRef);
        time:Utc currentUtc = time:utcNow();
        time:Civil time = time:utcToCivil(currentUtc);
        _ = check task:scheduleOneTimeJob(new Job(self.config, self.driveClient, self, self.dispatcherService), time);
    }

    public isolated function 'start() returns error? {
        check self.httpListener.attach(self.dispatcherService, ());
        check self.httpListener.'start();
    }

    public isolated function detach(GenericServiceType serviceRef) returns @tainted error? {
        check stopWatchChannel(self.driveConnection, self.channelUuid, self.watchResourceId);
        log:printDebug("Unsubscribed from the watch channel ID : " + self.channelUuid);
        string serviceTypeStr = self.getServiceTypeStr(serviceRef);
        check self.dispatcherService.removeServiceRef(serviceTypeStr);
    }

    public isolated function gracefulStop() returns @tainted error? {
        check stopWatchChannel(self.driveConnection, self.channelUuid, self.watchResourceId);
        log:printDebug("Unsubscribed from the watch channel ID : " + self.channelUuid);
        return self.httpListener.gracefulStop();
    }

    public isolated function immediateStop() returns @tainted error? {
        check stopWatchChannel(self.driveConnection, self.channelUuid, self.watchResourceId);
        log:printDebug("Unsubscribed from the watch channel ID : " + self.channelUuid);
        return self.httpListener.immediateStop();
    }
    private isolated function getServiceTypeStr(GenericServiceType serviceRef) returns string {
        return "DriveService";
    }
}

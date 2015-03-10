#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors_csgo>

#pragma semicolon 1

#define VERSION "1.3.0"
#define NAME "Observe Client"

#define ADMINFLAG ADMFLAG_GENERIC

public Plugin:myinfo = 
{
	name = NAME,
	author = "WhiteWolf, puopjik, psychonic, RedSword, Icon315",
	description = "Observe client when dead. Added damage messages, for admining purposes",
	version = VERSION,
	url = "http://www.whitewolf.us"
};

/* Credits:
	Mani - Showed me his observer code from MAP
*/

/* Globals */
new g_offObserverTarget;
new g_clientObserveTarget[MAXPLAYERS+1];
new bool:g_useSteamBans = false;

//CSGO-related
new bool:g_isCSGO;
new Handle:g_hSpec_freeze_time;
new Handle:g_hSpec_freeze_traveltime;
new Handle:g_hSpec_freeze_deathanim_time;


public OnPluginStart() {
	new Handle:conVar;
	
	CreateConVar("observe_version", VERSION, NAME, FCVAR_SPONLY|FCVAR_NOTIFY);
	
	HookEvent("player_spawn", EventPlayerSpawn);
	HookEvent("player_death", EventPlayerDeath);
	
	
	RegAdminCmd("sm_observe", CommandObserve, ADMINFLAG, "Spectate a player when dead.");
	RegAdminCmd("sm_endobserve", CommandEndObserve, ADMINFLAG, "End spectating a player.");
	
	LoadTranslations("common.phrases");
	LoadTranslations("observe.phrases");
	
	g_offObserverTarget = FindSendPropOffs("CBasePlayer", "m_hObserverTarget");
	if(g_offObserverTarget == -1) {
		SetFailState("Expected to find the offset to m_hObserverTarget, couldn't.");
	}
	
	conVar = FindConVar("sbsrc_version");
	if(conVar != INVALID_HANDLE) {
		g_useSteamBans = true;
	}
	for(new i = 0; i < MaxClients; i++)
    {
        if(isValidHumanClient(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
	decl String:szBuffer[ 8 ];
	
	GetGameFolderName(szBuffer, sizeof(szBuffer));
	
	g_isCSGO = StrEqual(szBuffer, "csgo", false);
	if (g_isCSGO)
	{
		g_hSpec_freeze_time = FindConVar("spec_freeze_time");
		g_hSpec_freeze_traveltime = FindConVar("spec_freeze_traveltime");
		g_hSpec_freeze_deathanim_time = FindConVar("spec_freeze_deathanim_time");
	}
}

/********************************************************************************
	Events
*********************************************************************************/
public OnClientPutInServer(i){
        if(isValidHumanClient(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if(isValidHumanClient(attacker) && isValidHumanClient(victim)){
        for(new i = 0; i < MaxClients; i++)
        {
            if(g_clientObserveTarget[i] == attacker && GetClientTeam(attacker) != GetClientTeam(victim)){
                new String:victimname[MAX_NAME_LENGTH];
                new String:attackername[MAX_NAME_LENGTH];
                GetClientName(attacker,attackername,sizeof(attackername));
                GetClientName(victim, victimname,sizeof(victimname));
                CPrintToChat(i, "%t", "Damage Given", attackername, victimname,damage);
           }
        }
        return Plugin_Continue;
    }
    return Plugin_Continue;
}

public Action:EventPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
	/* Suggestions for improvement, or single-shot method? */
	new target = GetClientOfUserId(GetEventInt(event, "userid"));
	for(new client = 1; client <= MaxClients; client++) {
		if(g_clientObserveTarget[client] == target && (IsClientObserver(client) || !IsPlayerAlive(client))) {
			SetClientObserver(client, target, true);
			return Plugin_Handled;
		}
	}
	return Plugin_Handled;
}

public Action:EventPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	
	new userId = GetEventInt(event, "userid");
	
	if (!g_isCSGO)
	{
		Timer_Death(INVALID_HANDLE, userId);
	}
	else
	{
		CreateTimer(GetConVarFloat(g_hSpec_freeze_time) + 
			GetConVarFloat(g_hSpec_freeze_traveltime) + 
			GetConVarFloat(g_hSpec_freeze_deathanim_time) +
			0.1, Timer_Death, userId ); //0.1 is needed; tested
	}
	
	return Plugin_Handled;
}

public Action:Timer_Death(Handle:timer, any:userId)
{
	new client = GetClientOfUserId(userId);
	
	if (g_isCSGO && client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		return Plugin_Handled;//prevent late kill messages
	}
	
	//Won't be a real Timer
	if(g_clientObserveTarget[client] > 0) {
		new target = g_clientObserveTarget[client];
		if(!isValidHumanClient(target)) {
			g_clientObserveTarget[client] = 0;
			return Plugin_Handled;
		}
		
		if(IsPlayerAlive(target)) {
			SetClientObserver(client, target, true);
		}
	}
	return Plugin_Handled;
}

public OnClientDisconnect(client) {
	new String:clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, MAX_NAME_LENGTH);
	
	g_clientObserveTarget[client] = 0;
	for(new i = 1; i <= MaxClients; i++) {
		if(g_clientObserveTarget[i] == client) {
			g_clientObserveTarget[i] = 0;
			if (IsClientInGame(i) && IsClientConnected(i)) {
				CPrintToChat(i, "%t", "Target Left", clientName);
			}
		}
	}
}

/********************************************************************************
	Commands
*********************************************************************************/

public Action:CommandEndObserve(client, args) {
	g_clientObserveTarget[client] = 0;
	CPrintToChat(client, "%t", "End Observe");
	return Plugin_Handled;
}

public Action:CommandObserve(client, args) {
	if(GetCmdArgs() < 1) {
		ReplyToCommand(client, "Usage: sm_observe <name or #userid>");
		return Plugin_Handled;
	}
	
	decl String:targetName[MAX_NAME_LENGTH], String:targetSteamID[MAX_NAME_LENGTH];
	
	GetCmdArg(1, targetName, sizeof(targetName)); //get username part from arguments
	
	new targetClient = FindTarget(client, targetName, false, false);
	if(targetClient == -1) {
		CPrintToChat(client, "%t", "Unknown Target");
		return Plugin_Handled;
	}
	
	GetClientName(targetClient, targetName, sizeof(targetName));
	GetClientAuthId(targetClient,AuthId_Steam2, targetSteamID, sizeof(targetSteamID));
	g_clientObserveTarget[client] = targetClient;
	
	if(IsClientObserver(client) || !IsPlayerAlive(client)) {
		if(!SetClientObserver(client, targetClient, true)) {
			CPrintToChat(client, "%t", "Observe Failed", targetName);
		}
	} else {
		CPrintToChat(client, "%t", "Observe on Spec", targetName, targetSteamID);
	}
	
	return Plugin_Handled;
}

/********************************************************************************
	Helper Methods
*********************************************************************************/

public bool:isValidHumanClient(client) {
	if(client > 0 && IsClientInGame(client) && IsClientConnected(client)) {
		return true;
	}
	return false;
}
		
public bool:SetClientObserver(client, target, bool:sendMessage) {
	if(!isValidHumanClient(client) || !isValidHumanClient(target)) {
		return false;
	}
	
	SetEntDataEnt2(client, g_offObserverTarget, target, true);
	
	if(sendMessage) {
		SendClientObserveMessage(client, target);
	}
	
	if(g_useSteamBans) {
		ClientCommand(client, "sb_status");
	}
		
	return true; //we assume it went through, else SM would throw a native error and we wouldn't get here anyway
}

public SendClientObserveMessage(client, target) {
	decl String:targetName[MAX_NAME_LENGTH], String:targetSteamID[65];
	GetClientName(target, targetName, MAX_NAME_LENGTH);
	GetClientAuthId(target,AuthId_Steam2, targetSteamID, 65);
	CPrintToChat(client, "%t", "Observing", targetName, targetSteamID);
}

/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <colors>
#undef REQUIRE_PLUGIN
#include <veterans>
#include <updater>
#include <SteamWorks>

#define IsValidClient(%1)		(1 <= %1 <= MaxClients && IsClientInGame(%1))
#define IsValidAliveClient(%1)	(1 <= %1 <= MaxClients && IsClientInGame(%1) && IsPlayerAlive(%1))
#define GETBOTINTERVAL 3.0

public Plugin myinfo =
{
	name = "simple join",
	author = "东",
	description = "A plugin designed CompetitiveWithAnne package change player team.",
	version = "1.1",
	url = "https://github.com/fantasylidong/CompetitiveWithAnne"
};

bool  
	g_bEnableGetbotCommand[MAXPLAYERS] = { false };

ConVar
	hCvarEnableInf,
	hCvarKickFamilyAccount;


public void OnPluginStart()
{
	hCvarEnableInf = CreateConVar("join_enable_inf", "0", "是否可以开启加入特感", _, true, 0.0, true, 1.0);
	hCvarKickFamilyAccount = CreateConVar("join_enable_kickfamilyaccount", "1", "是否开启踢出家庭共享账户", _, true, 0.0, true, 1.0);
	AddCommandListener(Command_Setinfo, "jointeam");
	AddCommandListener(Command_Setinfo1, "chooseteam");
	//RegConsoleCmd("sm_getbot", GetBot);
	HookEvent("player_team", Event_PlayerTeam);
}

public void SteamWorks_OnValidateClient(int ownerauthid, int authid)
{
	if (ownerauthid > 0 && ownerauthid != authid && hCvarKickFamilyAccount.BoolValue)
	{
		char SteamID[32];
		Format(SteamID, 32, "STEAM_1:%d:%d", (authid & 1), (authid >> 1));
		int client = GetIndexBySteamID(SteamID);
		if (client != -1)
		{
			KickClient(client, "家庭共享账户无法进入本服务器组");
		}
	}
}

int GetIndexBySteamID(const char[] SteamID)
{
	char AuthStringToCompareWith[32];
	for (int i = 1; i <= MaxClients; i++)
	{ 
		if (IsClientConnected(i) && GetClientAuthId(i, AuthId_Steam2, AuthStringToCompareWith, sizeof(AuthStringToCompareWith)) && StrEqual(AuthStringToCompareWith, SteamID))
		{
			return i;
		}
	}
	return -1;
}

public Action RestartMap(int client,int args)
{
	CrashMap();
	return Plugin_Handled;
}

void CrashMap()
{
	char mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	ServerCommand("changelevel %s", mapname);
}

public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetEventInt(event, "userid");
	int target = GetClientOfUserId(client);
	int team = GetEventInt(event, "team");
	bool disconnect = GetEventBool(event, "disconnect");
	if (IsValidPlayer(target) && !disconnect && team == 3 && !hCvarEnableInf.BoolValue)
	{
		if(!IsFakeClient(target))
		{
			CreateTimer(0.5, Timer_CheckDetay2, target, TIMER_FLAG_NO_MAPCHANGE);
		}else{
			return Plugin_Handled;
		}
	}
	//CreateTimer(0.1, Timer_MobChange, 0, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_CheckDetay2(Handle Timer, int client)
{
	ChangeClientTeam(client, 1); 
	return Plugin_Continue;
}



public Action Timer_CheckDetay(Handle Timer, int client)
{
	if(IsValidPlayerInTeam(client, 3))
	{
		ChangeClientTeam(client, 1); 
	}
	return Plugin_Continue;
}

public Action TurnClientToInfected(int client, int args) 
{
	if(!IsInfectTeamFull() && hCvarEnableInf.BoolValue)
	{
		ClientCommand(client, "jointeam infected");
	}
	return Plugin_Handled;
}

void checkbot(){
	int count=0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			count++;
		}
	}
	for(;count < FindConVar("survivor_limit").IntValue; count++){
		ServerCommand("sb_add");
	}	
}

public Action TurnClientToSurvivors(int client, int args)
{ 
	checkbot();
	if(!IsSuivivorTeamFull())
	{
		ClientCommand(client, "jointeam survivor");
	}
	return Plugin_Handled;
}

public Action AFKTurnClientToSpe(int client, int args) 
{
	if(!IsPinned(client))
		CreateTimer(1.0, Timer_CheckDetay2, client, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action Command_Setinfo(int client, const char[] command, int args)
{
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if (!hCvarEnableInf.BoolValue && (!StrEqual(arg, "survivor") || IsSuivivorTeamFull()))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
} 

public Action Command_Setinfo1(int client, const char[] command, int args)
{
	if(hCvarEnableInf.BoolValue){
    	return Plugin_Continue;
	}
	else
	{
		return Plugin_Handled;
	}
} 

public Action GetBot(int client, int args) 
{
	if(!IsValidClient(client))
		return Plugin_Handled;
	if(!g_bEnableGetbotCommand[client]){
		PrintToChat(client,"\x03 你使用命令的速度太快了");
	}
	else if(IsSuivivorTeamFull()){
		PrintToChat(client,"\x03 生还者团队已满，无其他生还者bot可供接管");
	}else{
		DrawSwitchCharacterMenu(client);
		g_bEnableGetbotCommand[client] = false;
		CreateTimer(GETBOTINTERVAL, ReEnableGetbotCommand, client);
	}
	return Plugin_Handled;
}

public Action ReEnableGetbotCommand(Handle timer, int client)
{
	g_bEnableGetbotCommand[client] = true;
	return Plugin_Stop;
}

public void DrawSwitchCharacterMenu(int client)
{
	Menu menu = new Menu(SwitchCharacterMenuHandler);
	menu.SetTitle("请选择喜欢的人物：");
	// 添加 Bot 到菜单中
	int menuindex = 0;
	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (IsClientInGame(bot))
		{
			char botid[32], botname[32], menuitem[8];
			GetClientName(bot, botname, sizeof(botname));
			GetClientAuthId(bot, AuthId_Steam2, botid, sizeof(botid));
			if (strcmp(botid, "BOT") == 0 && GetClientTeam(bot) == 2)
			{
				GetClientName(bot, botname, sizeof(botname));
				IntToString(menuindex, menuitem, sizeof(menuitem));
				menu.AddItem(menuitem, botname);
				menuindex++;
			}
		}
	}
	menu.ExitButton = true;
	menu.Display(client, 20);
}

public int SwitchCharacterMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char botname[32];
		GetMenuItem(menu, param2, botname, sizeof(botname), _, botname, sizeof(botname));
		ChangeClientTeam(param1, 1);
		ClientCommand(param1, "jointeam survivor %s", botname);
		//DataPack  dp;
		//dp.WriteCell(param1);
		//dp.WriteString(botname);
		//CreateTimer(1.0, ChangeTeam, dp);
	}
	else if (action == MenuAction_Cancel)
	{
		delete menu;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}
/*
public Action ChangeTeam(Handle timer, DataPack  dp){
	dp.Reset();
	char botname[32];
	int client = dp.ReadCell();
	dp.ReadString(botname, 32);
	ClientCommand(client, "jointeam survivor %s", botname);
	return Plugin_Continue;
}
*/

//判断特感是否已经满人
stock bool IsInfectTeamFull() 
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 3)
		{
			count ++;
		}
	}
	if(count >= FindConVar("z_max_player_zombies").IntValue){
		return true;
	}		
	else
	{
		return false;
	}
}

//判断生还是否已经满人
stock bool IsSuivivorTeamFull() 
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && IsFakeClient(i))
		{
			return false;
		}
	}
	return true;
}
//判断是否为生还者
stock bool IsSurvivor(int client) 
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2) 
	{
		return true;
	} 
	else 
	{
		return false;
	}
}

//判断是否为玩家再队伍里
stock bool IsValidPlayerInTeam(int client,int team)
{
	if(IsValidPlayer(client))
	{
		if(GetClientTeam(client)==team)
		{
			return true;
		}
	}
	return false;
}

stock bool IsValidPlayer(int client, bool AllowBot = true, bool AllowDeath = true)
{
	if (client < 1 || client > MaxClients)
		return false;
	if (!IsClientConnected(client) || !IsClientInGame(client))
		return false;
	if (!AllowBot)
	{
		if (IsFakeClient(client))
			return false;
	}

	if (!AllowDeath)
	{
		if (!IsPlayerAlive(client))
			return false;
	}	
	
	return true;
}

//判断生还者是否已经被控
stock bool IsPinned(int client) 
{
	bool bIsPinned = false;
	if (IsSurvivor(client)) 
	{
		if( GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0 ) bIsPinned = true; // smoker
		if( GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 ) bIsPinned = true; // hunter
		if( GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0 ) bIsPinned = true; // charger carry
		if( GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0 ) bIsPinned = true; // charger pound
		if( GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0 ) bIsPinned = true; // jockey
	}		
	return bIsPinned;
}
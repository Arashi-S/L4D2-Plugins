#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define CVAR_FLAGS FCVAR_NOTIFY

#define PLUGIN_VERSION "2.2"

public Plugin myinfo = 
{
	name = "Tank Anti-Stuck",
	author = "Dragokas, X光",
	description = "Teleport tank if he was stuck within collision and can't move",
	version = PLUGIN_VERSION,
	url = "https://github.com/dragokas"
}

/*
	ChangeLog:
	
	2.2 (03-Sep-2019)
	 - Returned to the previous stuck detection method (radius position-based)
	 with removing false positives when tank finishes off incapped player nearby or attacking in place.
	 - Some code optimizations, comments, removed some unused.
	 - "On ladder" logic is changed.
	
	2.1 (09-Aug-2019)
	 - Prevent rush punishment when tank count is 1 elapsed
	 - Tank is react faster when he is blocked on the ladder
	
	2.0 (05-May-2019)
	 - Collision with another clients (include other tanks) is now not considered as stuck.
	 - Fixed case when TR_DidHit() could return wrong result due to extracting info from global trace.
	 - Added "l4d_TankAntiStuck_dest_object" ConVar to control the destination, 
	 where you want to teleport tank to:
	 (0 - next to current tank, 1 - next to another tank, 2 - next to player). By default: 1 (previously, it was: 2).
	 
	 - Added new violations (punishment is teleporting tank directly to player):
	 1. Punish the player who doesn't move (tank stucker / inactive player)
	 2. Punish the player who rush too far from the nearest tank (and thus, from the team, including team rush).
	 
	 Punishments are enabled by default. To disable, use below ConVars:
	  - l4d_TankAntiStuck_idler_punish
	  - l4d_TankAntiStuck_rusher_punish
	 
	 For detail adjustments, see more new ConVars in the thread.
	 
	 - Code optimization
	 - Tank angry detection is improved
	 - Tank stuck detection is improved to avoid false positives
	 
	1.3 
	 - Added some missing ConVar hooks.
	
	1.2 (05-Mar-2019)
	 - Added all user's ConVars.
	 - Added late loading code.
	 - Included anti-losing tank control ConVar (thanks to cravenge)
	
	1.1 (01-Mar-2019)
	 - Added more reliable logic
	
	1.0 (05-Jan-2019)
	 - Initial release
	 
==========================================================================================

	Credits:
	
*	Peace-Maker - for some examples on TraceHull filter.

*	stinkyfax - for examples of teleporting in direction math.

*	cravenge - for some ConVar, possibly, preventing tank from losing control when getting stuck.

* 	midnight9, PatriotGames - who tried to help me with another ConVars against losing tank control.

==========================================================================================

	Related topics:
	https://forums.alliedmods.net/showthread.php?t=313696
	https://forums.alliedmods.net/showthread.php?p=2133193
	https://forums.alliedmods.net/showthread.php?t=101998
	
*/

#define DEBUG 0

ConVar g_hCvarEnable;
ConVar g_hCvarNonAngryTime;
ConVar g_hCvarTankDistanceMax;
ConVar g_hCvarHeadHeightMax;
ConVar g_hCvarHeadHeightMin;
ConVar g_hCvarStuckInterval;
ConVar g_hCvarNonStuckRadius;
ConVar g_hCvarAllIntellect;
ConVar g_hCvarApplyConVar;
ConVar g_hCvarStuckFailsafe;
ConVar g_hCvarTankClawRangeDown;
ConVar g_hCvarTankClawRange;
ConVar g_hCvarDestObject;
ConVar g_hCvarRusherPunish;
ConVar g_hCvarRusherDist;
ConVar g_hCvarRusherCheckTimes;
ConVar g_hCvarRusherCheckInterv;
ConVar g_hCvarRusherMinPlayers;
ConVar g_hCvarRusherEnable;

Handle g_hTimerIdler = INVALID_HANDLE;
Handle g_hTimerRusher = INVALID_HANDLE;

float g_pos[MAXPLAYERS+1][3];
float g_fMaxNonAngryDist;
float g_fNonAngryTime;
float g_fTankClawRange;

bool g_bLeft4Dead2;
bool g_bAngry[MAXPLAYERS+1];
bool g_bMapStarted = true;
bool g_bLateload;
bool g_bAtLeastOneTankAngry;

int g_bEnabled;
int g_iTanksCount;
int g_iTimes[MAXPLAYERS+1];
int g_iStuckTimes[MAXPLAYERS+1];
int g_iIdleTimes[MAXPLAYERS+1];
int g_iRushTimes[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if (test == Engine_Left4Dead2) {
		g_bLeft4Dead2 = true;
	}
	else if (test != Engine_Left4Dead) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	g_bLateload = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("l4d_TankAntiStuck_version", PLUGIN_VERSION, "插件版本", FCVAR_DONTRECORD);
	g_hCvarEnable = CreateConVar("l4d_TankAntiStuck_enable",							"1",	"是否开启插件(1=开, 0=关)", CVAR_FLAGS);

	g_hCvarNonAngryTime = CreateConVar("l4d_TankAntiStuck_non_angry_time",				"30",	"如果在指定的时间(秒)里坦克出现但没有行动(响起BGM)则自动传送坦克(0=禁用)", CVAR_FLAGS);
	g_hCvarTankDistanceMax = CreateConVar("l4d_TankAntiStuck_tank_distance_max",		"2000",	"坦克与最近的幸存者允许的最远距离(BGM响起时). 如果超过这个距离则传送坦克 (0=禁用)", CVAR_FLAGS);
	g_hCvarHeadHeightMax = CreateConVar("l4d_TankAntiStuck_head_height_max",			"20",	"当坦克判定为卡住时(距离太远没在指定时间到达幸存者也判定为卡住),坦克传送到玩家旁边最大高度,如果找不到位置传送失败尝试平滑传送", CVAR_FLAGS);
	g_hCvarHeadHeightMin = CreateConVar("l4d_TankAntiStuck_head_height_min",			"10",	"当坦克判定为卡住时(距离太远没在指定时间到达幸存者也判定为卡住),坦克传送到玩家旁边最小高度,如果找不到位置传送失败尝试平滑传送", CVAR_FLAGS);
	g_hCvarStuckInterval = CreateConVar("l4d_TankAntiStuck_check_interval",				"5",	"每次过这么久(秒)检测一次坦克是否被卡住", CVAR_FLAGS);

	g_hCvarNonStuckRadius = CreateConVar("l4d_TankAntiStuck_non_stuck_radius",			"50",	"在指定秒内未移动时,坦克被判定为未卡住的最大半径", CVAR_FLAGS);
	g_hCvarDestObject = CreateConVar("l4d_TankAntiStuck_dest_object",					"0",	"坦克传送到什么物体旁边(0=当前坦克附近, 1=别的坦克附近, 2=随机幸存者附近, 3=最前方幸存者附近)", CVAR_FLAGS);
	g_hCvarAllIntellect = CreateConVar("l4d_TankAntiStuck_all_intellect",				"1",	"防卡死应用的目标(1=玩家和BOT, 0=只有BOT)", CVAR_FLAGS);
	g_hCvarApplyConVar = CreateConVar("l4d_TankAntiStuck_apply_convar",					"1",	"防止坦克因为卡住而自杀(1=是, 0=否)", CVAR_FLAGS);

	g_hCvarRusherPunish = CreateConVar("l4d_TankAntiStuck_rusher_punish",				"1",	"是否惩罚(把坦克传送到他附近)跑图(出了坦克不打,一个人跑)的玩家?(0=否, 1=是)", CVAR_FLAGS);
	g_hCvarRusherDist = CreateConVar("l4d_TankAntiStuck_rusher_dist",					"2000",	"离坦克这么远被认为是在跑图", CVAR_FLAGS);
	g_hCvarRusherCheckTimes = CreateConVar("l4d_TankAntiStuck_rusher_check_times",		"2",	"如果连续被检测这么多次玩家在跑图确认玩家在跑图", CVAR_FLAGS);
	g_hCvarRusherCheckInterv = CreateConVar("l4d_TankAntiStuck_rusher_check_interval",	"5",	"每次经过这么久(秒)检测一次玩家是否跑图", CVAR_FLAGS);
	g_hCvarRusherMinPlayers = CreateConVar("l4d_TankAntiStuck_rusher_minplayers",		"2",	"至少要这么多玩家才考虑检查是否有人跑图", CVAR_FLAGS);
	g_hCvarRusherEnable = CreateConVar("l4d_TankAntiStuck_rusher_Enable",				"0",	"救援关是否检测跑图(1=是, 0=否)", CVAR_FLAGS);

	//AutoExecConfig(true, "l4d_tank_antistuck");

	g_hCvarStuckFailsafe = FindConVar("tank_stuck_failsafe");
	g_hCvarTankClawRange = FindConVar("claw_range");
	g_hCvarTankClawRangeDown = FindConVar("claw_range_down");

	#if (DEBUG)
		//test staff
		RegAdminCmd("sm_findempty", Cmd_FindEmpty, ADMFLAG_ROOT, "Find empty location next to the player and try teleport player there");
	#endif
	
	HookConVarChange(g_hCvarEnable,				ConVarChanged);
	HookConVarChange(g_hCvarTankDistanceMax,	ConVarChanged);
	HookConVarChange(g_hCvarNonAngryTime,		ConVarChanged);
	HookConVarChange(g_hCvarRusherPunish,		ConVarChanged);
	HookConVarChange(g_hCvarRusherEnable,		ConVarChanged);
	
	GetCvars();
	
	if (g_bLateload && g_bEnabled) {
		for (int i = 1; i <= MaxClients; i++) {
			if (i != 0 && IsClientInGame(i) && CheckTankIntellect(i)) {
				if (IsTank(i))
					BeginTankTracing(i);
			}
		}
	}
}

bool CheckTankIntellect(int tank)
{
	if (g_hCvarAllIntellect.BoolValue)
		return true;
	else
		if (IsFakeClient(tank)) {
			return true;
		}
	return false;
}

public void OnConfigsExecuted()
{
	if (g_hCvarApplyConVar.BoolValue) {
		if (g_hCvarStuckFailsafe != null)
			g_hCvarStuckFailsafe.SetInt(0);
	}
	g_fTankClawRange = g_hCvarTankClawRangeDown.FloatValue;
	
	if (g_hCvarTankClawRange.FloatValue > g_fTankClawRange)
		g_fTankClawRange = g_hCvarTankClawRange.FloatValue;
	
	g_fTankClawRange *= 2; // to be sure
}

public void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_bEnabled = g_hCvarEnable.BoolValue;
	g_fMaxNonAngryDist = g_hCvarTankDistanceMax.FloatValue;
	g_fNonAngryTime = g_hCvarNonAngryTime.FloatValue;

	InitHook();
}

void InitHook()
{
	static bool bHooked;
	
	if (g_bEnabled) {
		if (!bHooked) {
			HookEvent("tank_spawn",       		Event_TankSpawn,  		EventHookMode_Post);
			HookEvent("player_death",   		Event_PlayerDeath,		EventHookMode_Pre);
			HookEvent("round_start", 			Event_RoundStart,		EventHookMode_PostNoCopy);
			HookEvent("round_end", 				Event_RoundEnd,			EventHookMode_PostNoCopy);
			HookEvent("finale_win", 			Event_RoundEnd,			EventHookMode_PostNoCopy);
			HookEvent("mission_lost", 			Event_RoundEnd,			EventHookMode_PostNoCopy);
			HookEvent("map_transition", 		Event_RoundEnd,			EventHookMode_PostNoCopy);
			HookEvent("player_disconnect", 		Event_PlayerDisconnect,	EventHookMode_Pre);
			bHooked = true;
		}
	} else {
		if (bHooked) {
			UnhookEvent("tank_spawn",			Event_TankSpawn,  		EventHookMode_Post);
			UnhookEvent("player_death",   		Event_PlayerDeath,		EventHookMode_Pre);
			UnhookEvent("round_start", 			Event_RoundStart,		EventHookMode_PostNoCopy);
			UnhookEvent("round_end", 			Event_RoundEnd,			EventHookMode_PostNoCopy);
			UnhookEvent("finale_win", 			Event_RoundEnd,			EventHookMode_PostNoCopy);
			UnhookEvent("mission_lost", 		Event_RoundEnd,			EventHookMode_PostNoCopy);
			UnhookEvent("map_transition", 		Event_RoundEnd,			EventHookMode_PostNoCopy);
			UnhookEvent("player_disconnect", 	Event_PlayerDisconnect,	EventHookMode_Pre);
			bHooked = false;
		}
	}
}

public Action Cmd_FindEmpty(int client, int args)
{
	float vEnd[3], vOrigin[3];
	
	GetClientAbsOrigin(client, vOrigin);
	
	if (FindEmptyPos(client, client, 300.0, vEnd)) {
		PrintToChat(client, "Empty pos is found, distance: %f", GetVectorDistance(vOrigin, vEnd));
		TeleportEntity(client, vEnd, NULL_VECTOR, NULL_VECTOR);
	}
	else {
		PrintToChat(client, "Cannot found empty pos!!!");
		
		float fSetDist = 100.0;
		
		CopyVector(vOrigin, vEnd);
		vEnd[0] -= fSetDist;
		float dist;
		if ((dist = GetDistanceToVec(client, vEnd)) >= fSetDist) {
			PrintToChat(client, "ray infinite. dist = %f", dist);
		}
		else {
			PrintToChat(client, "ray infinite. dist = %f", dist);
		}
		
	}
	return Plugin_Handled;
}

public bool AimTargetFilter(int entity, int mask)
{
	return (entity > MaxClients || !entity);
}

public void Event_RoundStart(Event hEvent, const char[] name, bool dontBroadcast) 
{
	OnMapStart();
}
public void Event_RoundEnd(Event hEvent, const char[] name, bool dontBroadcast) 
{
	OnMapEnd();
}

public void OnMapStart() {
	static int i;
	g_bMapStarted = true;
	g_bAtLeastOneTankAngry = false;
	g_hTimerIdler = INVALID_HANDLE;
	g_hTimerRusher = INVALID_HANDLE;
	for (i = 1; i < MaxClients; i++)
		g_iTimes[i] = 0;
}
public void OnMapEnd() {
	g_bMapStarted = false;
	g_iTanksCount = 0;
}

public void Event_TankSpawn(Event hEvent, const char[] name, bool dontBroadcast) 
{
	if (!g_bEnabled || !g_bMapStarted) return;
	
	static int client;
	client = GetClientOfUserId(hEvent.GetInt("userid"));
	
	if (CheckTankIntellect(client)) {
		#if (DEBUG)
			CreateTimer(2.0, Timer_EmulateStuck, GetClientUserId(client));
		#endif
		
		BeginTankTracing(client);
		BeginIdlerRusherTracing();
		
		#if (DEBUG)
			PrintToChatAll("%N (id: %i) 出现了.", client, client);
		#endif
	}
}

void BeginIdlerRusherTracing(bool bResetStat = true)
{
	if (g_hCvarRusherPunish.BoolValue) {
		
		if (bResetStat) {
			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i)) {
					GetClientAbsOrigin(i, g_pos[i]);
					g_iIdleTimes[i] = 0;
					g_iRushTimes[i] = 0;
				}
			}
		}
		if (g_hCvarRusherPunish.BoolValue) {
			if (g_hCvarRusherEnable.BoolValue && IsFinalMap() || !IsFinalMap())
			{
				if (g_hTimerRusher == INVALID_HANDLE)
					g_hTimerRusher = CreateTimer(g_hCvarRusherCheckInterv.FloatValue, Timer_CheckRusher, _, TIMER_REPEAT);
			}
		}
	}
}

public Action Timer_CheckRusher(Handle timer) {

	static float pos[3], postank[3], distance;
	static int tank, i;

	if (!g_bMapStarted) {
		g_hTimerRusher = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (!g_bAtLeastOneTankAngry)
		return Plugin_Continue;

	if (g_iTanksCount == 1)
		return Plugin_Continue;

	i = GetAheadSurvivor(); //获取最前方的幸存者

	if (i == 0) //如果没有幸存者则直接返回
		return Plugin_Continue;

	if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsIncapped(i) && !IsPlayerHeld(i)) {
		GetClientAbsOrigin(i, pos);
		if (GetSurvivorCountAlive() >= g_hCvarRusherMinPlayers.IntValue) {
			tank = GetNearestTank(i);
			if (tank != 0) {
				GetClientAbsOrigin(tank, postank);
				distance = GetVectorDistance(pos, postank, false);
				if (distance > g_hCvarRusherDist.FloatValue) {
					if (g_iRushTimes[i] >= g_hCvarRusherCheckTimes.IntValue) {
						pos[0] += 20.0;
						pos[1] += 20.0;
						pos[2] += 20.0;
						TeleportEntity(tank, pos, NULL_VECTOR, NULL_VECTOR);
						pos[0] -= 20.0;
						pos[1] -= 20.0;
						pos[2] -= 20.0;
						PrintToChatAll("\x04[提示]\x05惩罚传送\x03坦克%s\x05传送到跑图玩家\x03%N\x05身边.", GetPlayerName(tank, true), i);
						g_iRushTimes[i] = 0;
					}
					else
					{
						g_iRushTimes[i]++;
					}
				}
				else
				{
					g_iRushTimes[i] = 0;
				}
			}
		}
	}
	return Plugin_Continue;
}

public void Event_PlayerDeath(Event hEvent, const char[] name, bool dontBroadcast) 
{
	if (!g_bEnabled || !g_bMapStarted) return;

	static int client;
	client = GetClientOfUserId(hEvent.GetInt("userid"));

	if (client != 0) {
		if (IsTank(client)) {
			CreateTimer(1.0, Timer_UpdateTankCount, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else {
			if (GetClientTeam(client) == 2) {
				ResetClientStat(client);
			}
		}
	}
}

public void Event_PlayerDisconnect(Event hEvent, const char[] name, bool dontBroadcast) 
{
	ResetClientStat(GetClientOfUserId(hEvent.GetInt("userid")));
}

void ResetClientStat(int client)
{
	g_pos[client][0] = 0.0;
	g_pos[client][1] = 0.0;
	g_pos[client][2] = 0.0;
	g_iIdleTimes[client] = 0;
	g_iRushTimes[client] = 0;
}

public Action Timer_UpdateTankCount(Handle timer) {
	UpdateTankCount();
	return Plugin_Handled;
}

void UpdateTankCount() {
	static int cnt;
	cnt = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsTank(i))
			cnt++;
	
	g_iTanksCount = cnt;
	
	if (cnt == 0) {
		g_bAtLeastOneTankAngry = false;
	
		if (g_hTimerIdler != INVALID_HANDLE) {
			CloseHandle (g_hTimerIdler);
			g_hTimerIdler = INVALID_HANDLE;
		}
		if (g_hTimerRusher != INVALID_HANDLE) {
			CloseHandle (g_hTimerRusher);
			g_hTimerRusher = INVALID_HANDLE;
		}
	}
}

void BeginTankTracing(int client)
{
	g_iStuckTimes[client] = 0;
	g_bAngry[client] = false;
	GetClientAbsOrigin(client, g_pos[client]);

	// wait until somebody make tank angry to begin check for stuck
	CreateTimer(2.0, Timer_CheckAngry, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	if (g_fNonAngryTime != 0 && IsPlayerAlive(client) && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == 8) {
		// check if tank didnt't become angry within 45 sec
		CreateTimer(g_fNonAngryTime, Timer_CheckAngryTimeout, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

// Stuck emulation on the map "l4d_airport04_terminal"
public void Timer_EmulateStuck(Handle timer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	if (client != 0)
		EmulateStuck(client);
}

stock void EmulateStuck(int client) {
	char sMap[100];
	GetCurrentMap(sMap, sizeof(sMap));
	if (StrEqual(sMap, "l4d_airport04_terminal", false)) { // L4D1
		float pos[3] = {419.714569, 4453.435546, 296.932739};
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	}
}

public Action Timer_CheckAngry(Handle timer, int UserId)
{
	static int client;
	client = GetClientOfUserId(UserId);
	if (client != 0 && IsClientInGame(client) && IsPlayerAlive(client) && g_bMapStarted) {
		// became angry?
		if (IsAngry(client) || g_bAngry[client]) {
		
			#if (DEBUG)
				PrintToChatAll("%N 发起了进攻.", client);
			#endif
			
			g_bAtLeastOneTankAngry = true;
			
			// check if he is not moving within X sec.
			CreateTimer(g_hCvarStuckInterval.FloatValue, Timer_CheckPos, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Stop;
		}
	}
	else
		return Plugin_Stop;
	
	return Plugin_Continue;
}

bool IsAngry(int tank)
{
	if (GetEntProp(tank, Prop_Send, "m_zombieState") != 0)
		return true;
	
	if (GetEntProp(tank, Prop_Send, "m_hasVisibleThreats") != 0)
		return true;
		
	return false;
}

bool IsIncappedNearBy(float vOrigin[3])
{
	static int i;
	static float vOriginPlayer[3];
	
	for (i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && IsIncapped(i))
		{
			GetClientAbsOrigin(i, vOriginPlayer);
			if (GetVectorDistance(vOriginPlayer, vOrigin) <= g_fTankClawRange)
				return true;
		}
	}
	return false;
}

bool IsTankAttacking(int tank)
{
	return GetEntProp(tank, Prop_Send, "m_fireLayerSequence") > 0;
}

public Action Timer_CheckPos(Handle timer, int UserId)
{
	static int tank;
	tank = GetClientOfUserId(UserId);
	if (tank != 0 && IsClientInGame(tank) && IsPlayerAlive(tank) && g_bMapStarted) {
		
		static float pos[3];
		GetClientAbsOrigin(tank, pos);
		pos[2] += 20.0;
		L4D_WarpToValidPositionIfStuck(tank);
		static float distance;
		distance = GetVectorDistance(pos, g_pos[tank], false);
		
		if (distance < g_hCvarNonStuckRadius.FloatValue && !IsIncappedNearBy(pos) && !IsTankAttacking(tank)) {
			
			static bool bOnLadder;
			bOnLadder = IsOnLadder(tank);
			
			if (g_fMaxNonAngryDist != 0.0 && (GetDistanceToNearestClient(tank) > g_fMaxNonAngryDist || g_iStuckTimes[tank] > 2)) {
				// object selectable by ConVar => teleport only when tank looks like completely stuck
				TeleportToObject(tank);
			}
			else if (g_iStuckTimes[tank] > 1 || bOnLadder) {
				
				#if (DEBUG)
					int anim = GetEntProp(tank, Prop_Send, "m_nSequence");
					PrintToChatAll("%N stucked => micro-teleport, dist: %f, anim: %i", tank, distance, anim);
				#endif
				
				/*
				SetEntProp(tank, Prop_Send, "m_nSequence", 12);
				CreateTimer(0.5, Timer_SetWalk, GetClientUserId(tank), TIMER_FLAG_NO_MAPCHANGE);
				*/
			}
			g_iStuckTimes[tank]++;
			
			#if (DEBUG)
				PrintToChatAll("%N stuck ++: %i", tank, g_iStuckTimes[tank]);
			#endif

		}
		else {
			g_iStuckTimes[tank] = 0;
		}
		
		g_pos[tank] = pos;
	}
	else
		return Plugin_Stop;
	
	return Plugin_Continue;
}

public void Timer_SetWalk(Handle timer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	if (client != 0 && IsClientInGame(client) && IsPlayerAlive(client)) {
		#if (DEBUG)
			PrintToChatAll("%N movetype: walk", client);
		#endif
		SetEntityMoveType (client, MOVETYPE_WALK);
	}
}

public Action Timer_CheckAngryTimeout(Handle timer, int UserId)
{
	static int client;
	client = GetClientOfUserId(UserId);
	if (client != 0 && IsClientInGame(client) && IsPlayerAlive(client)) {
		if (GetEntProp(client, Prop_Send, "m_zombieState") == 0) {
			TeleportToObject(client);
		}
		// force angry flag to allow timer to begin check for position even if tank became angry but still not moving
		SetEntProp(client, Prop_Send, "m_zombieState", 1);
		g_bAngry[client] = true; // just in case
		g_bAtLeastOneTankAngry = true;
		
		#if (DEBUG)
			PrintToChatAll("%N 进攻超时.", client);
		#endif
	}
	return Plugin_Handled;
}

void TeleportToObject(int client) {

	static int target;
	
	switch(g_hCvarDestObject.IntValue) {
		case 0: { //当前坦克附近
			target = client;
		}
		case 1: { //别的坦克附近
			target = GetNearestTank(client);
			if (target <= 0)
				target = GetNearestSurvivor(client);
		}
		case 2: { //随机幸存者附近
			target = GetNearestSurvivor(client);
		}
		case 3: { //最前方幸存者附近
			target = GetAheadSurvivor();
		}
	}

	if (target != 0 && IsPlayerAlive(client) && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == 8) {
		static float pos[3];
		if (!FindEmptyPos(target, client, g_hCvarHeadHeightMax.FloatValue, pos)) {
			GetClientAbsOrigin(target, pos);
			pos[2] += g_hCvarHeadHeightMin.FloatValue;
		}
		pos[0] += 50.0;
		pos[1] += 50.0;
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		pos[0] -= 50.0;
		pos[1] -= 50.0;
		PrintToChatAll("\x04[提示]\x05防卡启动\x03坦克%s\x05%s传送到%s%s\x03%N\x05身边.", GetPlayerName(client, true), g_hCvarDestObject.IntValue != 3 ? "随机" : "", g_hCvarDestObject.IntValue == 3 ? "前方" : "", g_hCvarDestObject.IntValue >= 2 ? "玩家" : "", target);
	}
}

char[] GetPlayerName(int client, bool bPromptType)
{
	char sName[32];
	if (!IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == 8)
		FormatEx(sName, sizeof(sName), "%s%N", !bPromptType ? "" : "\x04", client);
	else
	{
		GetClientName(client, sName, sizeof(sName));
		SplitString(sName, "Tank", sName, sizeof(sName));
	}
	return sName;
}

float GetDistanceToNearestClient(int client) {
	static float tpos[3], spos[3], dist, mindist;
	static int i;
	mindist = 0.0;
	GetClientAbsOrigin(client, tpos);
	
	for (i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, spos);
			dist = GetVectorDistance(tpos, spos, false);
			if (dist < mindist || mindist < 0.1)
				mindist = dist;
		}
	}
	return mindist;
}

int GetAheadSurvivor() {
	float max_flow = 0.0;
	float tmp_flow, origin[3];
	int iAheadSurvivor = 0, iTemp;
	Address pNavArea;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			iTemp = i;
			GetClientAbsOrigin(i, origin);
			pNavArea = L4D2Direct_GetTerrorNavArea(origin);
			if (pNavArea == Address_Null) continue;

			tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
			if (tmp_flow >= max_flow) {
				max_flow = tmp_flow;
				iAheadSurvivor = iTemp;
			}
		}
	}
	return (iAheadSurvivor == 0) ? iTemp : iAheadSurvivor;
}

int GetNearestSurvivor(int client) {
	static float tpos[3], spos[3], dist, mindist;
	static int i, iNearClient;
	mindist = 0.0;
	iNearClient = 0;
	GetClientAbsOrigin(client, tpos);
	
	for (i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, spos);
			dist = GetVectorDistance(tpos, spos, false);
			if (dist < mindist || mindist < 0.1) {
				mindist = dist;
				iNearClient = i;
			}
		}
	}
	return iNearClient;
}

int GetNearestTank(int client) {
	static float tpos[3], spos[3], dist, mindist;
	static int iNearClient;
	iNearClient = 0;
	mindist = 0.0;
	GetClientAbsOrigin(client, tpos);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (i != client && IsTank(i)) {
			GetClientAbsOrigin(i, spos);
			dist = GetVectorDistance(tpos, spos, false);
			if (dist < mindist || mindist < 0.1) {
				mindist = dist;
				iNearClient = i;
			}
		}
	}
	return iNearClient;
}

stock bool IsTank(int client)
{
	if ( client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 3 )
	{
		int class = GetEntProp(client, Prop_Send, "m_zombieClass");
		if ( class == (g_bLeft4Dead2 ? 8 : 5 ))
			return true;
	}
	return false;
}

stock int GetAnySurvivor() {
	static int i;
	for (i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
			return i;
	}
	return 0;
}

int GetSurvivorCountAlive() {
	static int cnt, i;
	cnt = 0;
	for (i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
			cnt++;
	}
	return cnt;
}

public bool TraceRay_DontHitSelf(int iEntity, int iMask, any data)
{
	return (iEntity != data);
}

public bool TraceRay_NoPlayers(int entity, int mask, any data)
{
    if (entity == data || (entity >= 1 && entity <= MaxClients))
    {
        return false;
    }
    return true;
}

stock float GetDistanceToVec(int client, float vEnd[3]) // credits: Peace-Maker
{ 
	static float vMin[3], vMax[3], vOrigin[3], vStart[3], fDistance;
	fDistance = 0.0;
	GetClientAbsOrigin(client, vStart);
	vStart[2] += 10.0;
	GetClientMins(client, vMin);
	GetClientMaxs(client, vMax);
	GetClientAbsOrigin(client, vOrigin);
	Handle hTrace = TR_TraceHullFilterEx(vOrigin, vEnd, vMin, vMax, MASK_PLAYERSOLID, TraceRay_NoPlayers, client);
	
	if (hTrace != INVALID_HANDLE) {
		if (TR_DidHit(hTrace))
		{
			float fEndPos[3];
			TR_GetEndPosition(fEndPos, hTrace);
			vStart[2] -= 10.0;
			fDistance = GetVectorDistance(vStart, fEndPos);
		}
		else {
			vStart[2] -= 10.0;
			fDistance = GetVectorDistance(vStart, vEnd);
		}
		CloseHandle(hTrace);
	}
	return fDistance; 
}

bool FindEmptyPos(int client, int target, float fSetDist, float vEnd[3])
{
	static const float fClientHeight = 71.0;
	
	static float vMin[3], vMax[3], vStart[3];
	
	GetClientMins(target, vMin);
	GetClientMaxs(target, vMax);
	float fTargetHeigth = vMax[2] - vMin[2];
	
	GetClientAbsOrigin(client, vStart);
	
	//to the roof;
	CopyVector(vStart, vEnd);
	vEnd[2] += (fClientHeight + fSetDist);
	
	if (GetDistanceToVec(client, vEnd) >= (fClientHeight + fSetDist)) {
		vEnd[2] -= fTargetHeigth;
		return true;
	}

	//to the right
	CopyVector(vStart, vEnd);
	vEnd[0] += fSetDist;
	if (GetDistanceToVec(client, vEnd) >= fSetDist)
		return true;
	
	//to the left
	CopyVector(vStart, vEnd);
	vEnd[0] -= fSetDist;
	if (GetDistanceToVec(client, vEnd) >= fSetDist)
		return true;

	//to the forward
	CopyVector(vStart, vEnd);
	vEnd[1] += fSetDist;
	if (GetDistanceToVec(client, vEnd) >= fSetDist)
		return true;
		
	//to the backward
	CopyVector(vStart, vEnd);
	vEnd[1] -= fSetDist;
	if (GetDistanceToVec(client, vEnd) >= fSetDist)
		return true;
		
	//to the right + up
	CopyVector(vStart, vEnd);
	vEnd[0] += fSetDist;
	vEnd[2] += (fClientHeight + fSetDist);
	if (GetDistanceToVec(client, vEnd) >= fSetDist) {
		vEnd[2] -= fTargetHeigth;
		return true;
	}
	
	//to the left + up
	CopyVector(vStart, vEnd);
	vEnd[0] -= fSetDist;
	vEnd[2] += (fClientHeight + fSetDist);
	if (GetDistanceToVec(client, vEnd) >= fSetDist) {
		vEnd[2] -= fTargetHeigth;
		return true;
	}
	
	//to the forward + up
	CopyVector(vStart, vEnd);
	vEnd[1] += fSetDist;
	vEnd[2] += (fClientHeight + fSetDist);
	if (GetDistanceToVec(client, vEnd) >= fSetDist) {
		vEnd[2] -= fTargetHeigth;
		return true;
	}
	
	//to the backward + up
	CopyVector(vStart, vEnd);
	vEnd[1] -= fSetDist;
	vEnd[2] += (fClientHeight + fSetDist);
	if (GetDistanceToVec(client, vEnd) >= fSetDist) {
		vEnd[2] -= fTargetHeigth;
		return true;
	}
	
	if (fSetDist == 1.0)
		return false;
	
	fSetDist -= 30.0;
	
	if (fSetDist < 0.0)
		fSetDist = 1.0;
	
	FindEmptyPos(client, target, fSetDist, vEnd); // recurse => decrease a distance until found appropriate location
	return false;
}

void CopyVector(const float vecSrc[3], float vecDest[3]) {
	vecDest[0] = vecSrc[0];
	vecDest[1] = vecSrc[1];
	vecDest[2] = vecSrc[2];
}

stock bool IsOnLadder(int entity) {
	return GetEntityMoveType(entity) == MOVETYPE_LADDER;
}

stock bool IsIncapped(int client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1 || GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 1;
	// return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}

stock bool IsPlayerHeld(int client)
{
	int jockey = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
	int charger = GetEntPropEnt(client, Prop_Send, "m_pummelAttacker");
	int hunter = GetEntPropEnt(client, Prop_Send, "m_pounceAttacker");
	int smoker = GetEntPropEnt(client, Prop_Send, "m_tongueOwner");
	if (jockey > 0 || charger > 0 || hunter > 0 || smoker > 0)
	{
		return true;
	}
	return false;
}

stock bool IsFinalMap()
{
	return FindEntityByClassname(-1, "info_changelevel") == -1 && FindEntityByClassname(-1, "trigger_changelevel") == -1;
}
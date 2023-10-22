#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <left4dhooks>
#include <l4d2_ems_hud>

#define PLUGIN_NAME				"Server Info Hud"
#define PLUGIN_AUTHOR			"sorallll,豆瓣酱な,奈"
#define PLUGIN_DESCRIPTION		"结合sorallll和豆瓣酱な制作的hud"
#define PLUGIN_VERSION			"1.0.6"
#define PLUGIN_URL				"https://github.com/NanakaNeko/l4d2_plugins_coop"

enum struct KillData {
	int TotalSI;
	int TotalCI;

	void Clean() {
		this.TotalSI = 0;
		this.TotalCI = 0;
	}
}
char g_sWeekName[][] = {"一", "二", "三", "四", "五", "六", "日"};
char sDate[][] = {"天", "时", "分", "秒"};
//对抗模式.
char g_sModeVersus[][] = 
{
	"versus",		//对抗模式
	"teamversus ",	//团队对抗
	"scavenge",		//团队清道夫
	"teamscavenge",	//团队清道夫
	"community3",	//骑师派对
	"community6",	//药抗模式
	"mutation11",	//没有救赎
	"mutation12",	//写实对抗
	"mutation13",	//清道肆虐
	"mutation15",	//生存对抗
	"mutation18",	//失血对抗
	"mutation19"	//坦克派对?
};

//单人模式.
char g_sModeSingle[][] = 
{
	"mutation1", //孤身一人
	"mutation17" //孤胆枪手
};

KillData
	g_eData;

ConVar
	g_cVsBossBuff;

Handle
	g_hTimer;

bool
	g_bLateLoad;

float
	g_fMapRunTime,
	g_fVsBossBuff,
	g_fMapMaxFlow;

int
	g_iPlayerNum,
	g_iMaxChapters,
	g_iCurrentChapter;

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("server_info_version", PLUGIN_VERSION, "Server Info Hud plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_cVsBossBuff = FindConVar("versus_boss_buffer");
	g_cVsBossBuff.AddChangeHook(CvarChanged);

	HookEvent("round_end",		Event_RoundEnd,		EventHookMode_PostNoCopy);
	HookEvent("round_start",	Event_RoundStart,	EventHookMode_PostNoCopy);
	HookEvent("player_death",	Event_PlayerDeath,	EventHookMode_Pre);
	HookEvent("infected_death",	Event_InfectedDeath);

	g_fMapRunTime = GetEngineTime();

	if (g_bLateLoad)
		g_hTimer = CreateTimer(1.0, tmrUpdate, _, TIMER_REPEAT);
}

public void OnConfigsExecuted() {
	GetCvars();

	g_iMaxChapters = L4D_GetMaxChapters();
	g_iCurrentChapter = L4D_GetCurrentChapter();
	g_fMapMaxFlow = L4D2Direct_GetMapMaxFlowDistance();
}

void CvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	GetCvars();
}

void GetCvars() {
	g_fVsBossBuff =	g_cVsBossBuff.FloatValue;
}

//玩家连接
public void OnClientConnected(int client)
{   
	if (!IsFakeClient(client))
		g_iPlayerNum += 1;
}

//玩家离开.
public void OnClientDisconnect(int client)
{   
	if (!IsFakeClient(client))
		g_iPlayerNum -= 1;
}

public void OnMapStart() {
	g_iPlayerNum = 0;
	EnableHUD();
}

public void OnMapEnd() {
	delete g_hTimer;
	g_eData.Clean();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	delete g_hTimer;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	delete g_hTimer;
	g_hTimer = CreateTimer(1.0, tmrUpdate, _, TIMER_REPEAT);
}

Action tmrUpdate(Handle timer) {
	static int client;
	static float highestFlow;
	highestFlow = (client = L4D_GetHighestFlowSurvivor()) != -1 ? L4D2Direct_GetFlowDistance(client) : L4D2_GetFurthestSurvivorFlow();
	if (highestFlow)
		highestFlow = highestFlow / g_fMapMaxFlow * 100;

	static char buffer[128];
	FormatEx(buffer, sizeof buffer, "路程: %d％", RoundToCeil(highestFlow));

	static int flow;
	static int length;
	static int roundNumber;
	roundNumber = GameRules_GetProp("m_bInSecondHalfOfRound");
	if (L4D2Direct_GetVSTankToSpawnThisRound(roundNumber)) {
		flow = RoundToCeil(L4D2Direct_GetVSTankFlowPercent(roundNumber) * 100.0);
		if (flow > 0) {
			flow -= RoundToFloor(g_fVsBossBuff / g_fMapMaxFlow * 100);
			length = strlen(buffer);
			Format(buffer[length], sizeof buffer - length, " Tank#%d％", flow < 0 ? 0 : flow);
		}
	}

	if (L4D2Direct_GetVSWitchToSpawnThisRound(roundNumber)) {
		flow = RoundToCeil(L4D2Direct_GetVSWitchFlowPercent(roundNumber) * 100.0);
		if (flow > 0) {
			flow -= RoundToFloor(g_fVsBossBuff / g_fMapMaxFlow * 100);
			length = strlen(buffer);
			Format(buffer[length], sizeof buffer - length, " Witch#%d％", flow < 0 ? 0 : flow);
		}
	}

	char g_sDate[64], g_sTime[128];
	FormatTime(g_sDate, sizeof(g_sDate), "%Y-%m-%d %H:%M:%S");
	FormatEx(g_sTime, sizeof(g_sTime), "%s 星期%s%s", g_sDate, IsWeekName(), GetAddSpacesMax(3, " "));
	HUDSetLayout(HUD_MID_TOP, HUD_FLAG_ALIGN_LEFT|HUD_FLAG_NOBG|HUD_FLAG_TEXT, g_sTime);
	HUDPlace(HUD_MID_TOP, 0.70, 0.00, 1.0, 0.03);

	HUDSetLayout(HUD_SCORE_1, HUD_FLAG_TEXT|HUD_FLAG_NOBG|HUD_FLAG_ALIGN_LEFT, "%s", buffer);
	HUDPlace(HUD_SCORE_1, 0.70, 0.03, 1.0, 0.03);

	HUDSetLayout(HUD_SCORE_2, HUD_FLAG_TEXT|HUD_FLAG_NOBG|HUD_FLAG_ALIGN_LEFT, "人数: [%d/%d] 地图: [%d/%d]", g_iPlayerNum, GetMaxPlayers(), g_iCurrentChapter, g_iMaxChapters);
	HUDPlace(HUD_SCORE_2, 0.70, 0.06, 1.0, 0.03);

	HUDSetLayout(HUD_SCORE_3, HUD_FLAG_TEXT|HUD_FLAG_NOBG|HUD_FLAG_ALIGN_LEFT, "统计: 特感->%d 僵尸->%d", g_eData.TotalSI, g_eData.TotalCI);
	HUDPlace(HUD_SCORE_3, 0.70, 0.09, 1.0, 0.03);

	char g_sTotalTime[128];
	FormatEx(g_sTotalTime, sizeof(g_sTotalTime), "运行: %s", StandardizeTime(g_fMapRunTime));
	HUDSetLayout(HUD_SCORE_4, HUD_FLAG_TEXT|HUD_FLAG_NOBG|HUD_FLAG_ALIGN_LEFT, "%s", g_sTotalTime);
	HUDPlace(HUD_SCORE_4, 0.70, 0.12, 1.0, 0.03);

	return Plugin_Continue;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim) || GetClientTeam(victim) != 3)
		return;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!attacker || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2)
		return;

	g_eData.TotalSI++;
}

void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!attacker || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2)
		return;

	g_eData.TotalCI++;
}

//返回当前星期几.
char[] IsWeekName()
{
	char g_sWeek[8];
	FormatTime(g_sWeek, sizeof(g_sWeek), "%u");
	return g_sWeekName[StringToInt(g_sWeek) - 1];
}

//填入对应数量的内容.
char[] GetAddSpacesMax(int Value, char[] sContent)
{
	char g_sBlank[64];
	
	if(Value > 0)
	{
		char g_sFill[32][64];
		if(Value > sizeof(g_sFill))
			Value = sizeof(g_sFill);
		for (int i = 0; i < Value; i++)
			strcopy(g_sFill[i], sizeof(g_sFill[]), sContent);
		ImplodeStrings(g_sFill, sizeof(g_sFill), "", g_sBlank, sizeof(g_sBlank));//打包字符串.
	}
	return g_sBlank;
}

//返回最大人数.
int GetMaxPlayers()
{
	static Handle g_hMaxPlayers;
	g_hMaxPlayers = FindConVar("sv_maxplayers");
	if (g_hMaxPlayers == null)
		return GetDefaultNumber();
		
	int g_iMaxPlayers = GetConVarInt(g_hMaxPlayers);
	if(g_iMaxPlayers <= -1)
		return GetDefaultNumber();
	
	return g_iMaxPlayers;
}

int GetDefaultNumber()
{
	for (int i = 0; i < sizeof(g_sModeVersus); i++)
		if(strcmp(GetGameMode(), g_sModeVersus[i]) == 0)
			return 8;
	for (int i = 0; i < sizeof(g_sModeSingle); i++)
		if(strcmp(GetGameMode(), g_sModeSingle[i]) == 0)
			return 1;
	return 4;
}

char[] GetGameMode()
{
	char g_sMode[32];
	GetConVarString(FindConVar("mp_gamemode"), g_sMode, sizeof(g_sMode));
	return g_sMode;
}

//https://forums.alliedmods.net/showthread.php?t=288686
char[] StandardizeTime(float g_fRunTime)
{
	int iTime[4];
	char sName[128], sTime[4][32];
	float fTime[3] = {86400.0, 3600.0, 60.0};
	float remainder = GetEngineTime() - g_fRunTime;
	
	iTime[0] = RoundToFloor(remainder / fTime[0]);
	remainder = remainder - float(iTime[0]) * fTime[0];
	iTime[1] = RoundToFloor(remainder / fTime[1]);
	remainder = remainder - float(iTime[1]) * fTime[1];
	iTime[2] = RoundToFloor(remainder / fTime[2]);
	remainder = remainder - float(iTime[2]) * fTime[2];
	iTime[3] = RoundToFloor(remainder);

	for (int i = 0; i < sizeof(sTime); i++)
		if(iTime[i] > 0)
			FormatEx(sTime[i], sizeof(sTime[]), "%d%s", iTime[i], sDate[i]);
	ImplodeStrings(sTime, sizeof(sTime), "", sName, sizeof(sName));//打包字符串.
	return sName;
}

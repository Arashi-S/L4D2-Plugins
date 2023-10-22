#pragma semicolon 1
//強制1.7以後的新語法
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.5.0"

int l4d2_Switch;

int CountKIHenabled, CountKIHLimit, CountKIHNum, CountKIHNumoff, CountKIHuhealke, CountKIHurevive, CountKIHrescued, CountKIHWitch, CountKIHWitchIsHeadshot, CountKIHused, CountKIHTank;

ConVar hCountKIHenabled, hCountKIHNum, hCountKIHNumoff, hCountKIHTank, hCountKIHWitch, hCountKIHWitchIsHeadshot, hCountKIHLimit, hCountKIHused, hCountKIHSwitch, hCountKIHrevive, hCountKIHrescued, hCountKIHhealk;

bool HLReturnset;
bool l4d2_HLReturnset;

bool hCountKIH_Switch_true = true;

char clientName[32];

public Plugin myinfo =
{
	name = "加血奖励插件",
	author = "",
	description = "health return",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_onhp", OnHLReturn, "管理员开启击杀特感提示和血量奖励.");
	RegConsoleCmd("sm_offhp", OffHLReturn, "管理员关闭击杀特感提示和血量奖励.");
	
	HookEvent("witch_killed", KIHEvent_KillWitch);
	HookEvent("player_death", KIHEvent_KillInfected);
	HookEvent("tank_killed", KIHEvent_KillTank);
	HookEvent("witch_harasser_set", Witch_Harasser_event);//惊扰女巫
	HookEvent("defibrillator_used", Event_defibrillatorused);//幸存者使用电击器救活队友.
	HookEvent("revive_success", KIHEvent_revive);//救起幸存者
	HookEvent("survivor_rescued", evtSurvivorRescued);//幸存者在营救门复活.
	HookEvent("heal_success", HealSuccess);//幸存者治疗
	
	hCountKIHenabled		= CreateConVar("l4d2_Kill_enabled_health_return", "1", "启用幸存者血量奖励插件? (指令 !offhp 关闭, ) 0=禁用(总开关,禁用后指令开关也不可用), 1=启用.", FCVAR_NOTIFY);
	hCountKIHSwitch		= CreateConVar("l4d2_Kill_enabled_health_return_switch", "0", "设置默认开启或关闭血量奖励? (指令 !onhp 开启击杀提示和血量奖励, 再次输入指令只显示击杀提示) 0=关闭, 1=开启击杀提示, 2=开启击杀提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHNum			= CreateConVar("l4d2_Kill_inf_health_return", "5", "击杀一个特感奖励多少血量(不包括坦克). 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHNumoff		= CreateConVar("l4d2_Kill_inf_health_returnoff", "0", "启用击杀特感提示?(因为多特服特感太多,导致提示过于刷屏) 0=禁用, 1=启用.", FCVAR_NOTIFY);
	hCountKIHrevive		= CreateConVar("l4d2_Kill_revive_health_return", "10", "救起倒地的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHTank			= CreateConVar("l4d2_Kill_tank_health_return", "25", "杀死坦克的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHrescued		= CreateConVar("l4d2_Kill_rescued_health_return", "10", "营救队友的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHhealk			= CreateConVar("l4d2_Kill_heal_health_return", "15", "治疗队友的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHused			= CreateConVar("l4d2_Kill_sed_health_return", "20", "电击器复活队友的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHWitch			= CreateConVar("l4d2_Kill_witch_health_return", "15", "击杀女巫的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHWitchIsHeadshot	= CreateConVar("l4d2_Kill_witch_health_return_2", "25", "秒杀女巫的幸存者奖励多少血. 0=禁用提示和血量奖励.", FCVAR_NOTIFY);
	hCountKIHLimit			= CreateConVar("l4d2_health_Limit", "200", "设置幸存者获得血量奖励的最高上限(最小值100).", FCVAR_NOTIFY);
	
	hCountKIHNum.AddChangeHook(HealthConVarChanged);
	hCountKIHNumoff.AddChangeHook(HealthConVarChanged);
	hCountKIHrevive.AddChangeHook(HealthConVarChanged);
	hCountKIHTank.AddChangeHook(HealthConVarChanged);
	hCountKIHrescued.AddChangeHook(HealthConVarChanged);
	hCountKIHhealk.AddChangeHook(HealthConVarChanged);
	hCountKIHused.AddChangeHook(HealthConVarChanged);
	hCountKIHWitch.AddChangeHook(HealthConVarChanged);
	hCountKIHWitchIsHeadshot.AddChangeHook(HealthConVarChanged);
	hCountKIHLimit.AddChangeHook(HealthConVarChanged);
	
	AutoExecConfig(true, "l4d2_health_return");//生成指定文件名的CFG.
}

//地图开始.
public void OnMapStart()
{
	l4d2_HealthChange();
}

public void HealthConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	l4d2_HealthChange();
}

void l4d2_HealthChange()
{
	l4d2_Switch = hCountKIHSwitch.IntValue;
	CountKIHenabled = hCountKIHenabled.IntValue;
	CountKIHLimit = hCountKIHLimit.IntValue;
	if (CountKIHLimit < 100)
	{
		CountKIHLimit = 100;
	}
	CountKIHNum = hCountKIHNum.IntValue;
	CountKIHNumoff = hCountKIHNumoff.IntValue;
	CountKIHuhealke = hCountKIHhealk.IntValue;
	CountKIHurevive = hCountKIHrevive.IntValue;
	CountKIHrescued = hCountKIHrescued.IntValue;
	CountKIHWitch = hCountKIHWitch.IntValue;
	CountKIHWitchIsHeadshot = hCountKIHWitchIsHeadshot.IntValue;
	CountKIHused = hCountKIHused.IntValue;
	CountKIHTank = hCountKIHTank.IntValue;
}

public void OnConfigsExecuted()
{
	if(hCountKIH_Switch_true)
	{
		switch (l4d2_Switch)
		{
			case 0:
			{
				HLReturnset = false;
				l4d2_HLReturnset = false;
			}
			case 1:
			{
				HLReturnset = false;
				l4d2_HLReturnset = true;
			}
			case 2:
			{
				HLReturnset = true;
				l4d2_HLReturnset = true;
			}
		}
	}
}

public Action OffHLReturn(int client, int args)
{
	if(bCheckClientAccess(client) && iGetClientImmunityLevel(client) >= 98)
	{
		switch (CountKIHenabled)
		{
			case 0:
			{
				PrintToChat(client, "\x04[提示]\x05击杀特感坦克女巫提示和血量奖励已禁用,请在CFG中设为1启用.");
			}
			case 1:
			{
				if (l4d2_HLReturnset)
				{
					HLReturnset = false;
					l4d2_HLReturnset = false;
					hCountKIH_Switch_true = false;
					PrintToChatAll("\x04[提示]\x03已关闭\x05击杀特感坦克女巫血量奖励功能.");
				}
				else
				{
					HLReturnset = false;
					l4d2_HLReturnset = false;
					hCountKIH_Switch_true = false;
					PrintToChatAll("\x04[提示]\x03已关闭\x05击杀特感坦克女巫血量奖励功能.");
				}
			}
		}
	}
	else
		PrintToChat(client, "\x04[提示]\x05你无权使用此指令.");
	return Plugin_Handled;
}

public Action OnHLReturn(int client, int args)
{
	if(bCheckClientAccess(client) && iGetClientImmunityLevel(client) >= 98)
	{
		switch (CountKIHenabled)
		{
			case 0:
			{
				PrintToChat(client, "\x04[提示]\x05击杀特感坦克女巫提示和血量奖励已禁用,请在CFG中设为1启用.");
			}
			case 1:
			{
				if (!l4d2_HLReturnset)
				{
					if (HLReturnset)
					{
						HLReturnset = false;
						l4d2_HLReturnset = true;
						hCountKIH_Switch_true = false;
						//PrintToChatAll("\x04[提示]\x03已开启\x05击杀特感坦克女巫提示,禁用了血量奖励.");//聊天窗提示.
					}
					else
					{
						HLReturnset = true;
						l4d2_HLReturnset = true;
						hCountKIH_Switch_true = false;
						PrintToChatAll("\x04[提示]\x03已开启\x05击杀特感坦克女巫血量奖励,血量上限\x04%d\x05HP.", CountKIHLimit);
					}
				}
				else
				{
					if (HLReturnset)
					{
						HLReturnset = false;
						l4d2_HLReturnset = true;
						hCountKIH_Switch_true = false;
						//PrintToChatAll("\x04[提示]\x03已开启\x05击杀特感坦克女巫提示,禁用了血量奖励.");//聊天窗提示.
					}
					else
					{
						HLReturnset = true;
						l4d2_HLReturnset = true;
						hCountKIH_Switch_true = false;
						PrintToChatAll("\x04[提示]\x03已开启\x05击杀特感坦克女巫血量奖励,血量上限\x04%d\x05HP.", CountKIHLimit);
					}
				}
			}
		}
	}
	else
		PrintToChat(client, "\x04[提示]\x05你无权使用此指令.");
	return Plugin_Handled;
}

bool bCheckClientAccess(int client)
{
	if(GetUserFlagBits(client) & ADMFLAG_ROOT)
		return true;
	return false;
}

int iGetClientImmunityLevel(int client)
{
	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, sSteamID);
	if(admin == INVALID_ADMIN_ID)
		return -999;

	return admin.ImmunityLevel;
}

public void Witch_Harasser_event(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(client) && GetClientTeam(client) == 2)
		{
			GetTrueName(client, clientName);
			//PrintToChatAll("\x04[提示]\x03%s\x05惊扰了女巫.", clientName);//聊天窗提示.
		}
	}
}

public void HealSuccess(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int subject = GetClientOfUserId(event.GetInt("subject"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHuhealke == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		char subjectname[32];
		GetTrueName(client, clientName);
		GetTrueName(subject, subjectname);
		
		if (client == subject)
		{
			//PrintToChatAll("\x05[提示]\x04%s\x03治疗了自己.", clientName);//聊天窗提示.
			return;
		}
		if (GetClientTeam(client) == 2)
		{
			if (HLReturnset)
			{
				if (IsPlayerAlive(subject) && GetEntProp(subject, Prop_Send, "m_isIncapacitated") == 0)
				{
					int Attackerhealth = GetClientHealth(client);
					int tmphealth = L4D_GetPlayerTempHealth(client);
					
					if (tmphealth == -1)
					{
						tmphealth = 0;
					}
						
					if (Attackerhealth + tmphealth + CountKIHuhealke > CountKIHLimit)
					{
						float overhealth,fakehealth;
						overhealth = float(Attackerhealth + tmphealth + CountKIHuhealke - CountKIHLimit);
						if (tmphealth < overhealth)
						{
							fakehealth = 0.0;
						}
						else
						{
							fakehealth = float(tmphealth) - overhealth;
						}
						SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
						SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fakehealth);
					}
					if ((Attackerhealth + CountKIHuhealke) < CountKIHLimit)
					{
						SetEntProp(client, Prop_Send, "m_iHealth", Attackerhealth + CountKIHuhealke, 1);
					}
					else
					{
						SetEntProp(client, Prop_Send, "m_iHealth", CountKIHLimit, 1);
					}
					
					int Attackerhealth2 = Attackerhealth + tmphealth;
					
					if (Attackerhealth2 < CountKIHLimit)
					{
						PrintToChatAll("\x04[提示]\x03%s\x05治疗了\x03%s\x04,\x05奖励\x03%d\x05点血量.", clientName, subjectname, CountKIHuhealke);//聊天窗提示.
					}
					else
					{
						PrintToChatAll("\x04[提示]\x03%s\x05治疗了\x03%s\x04,\x05血量已达\x03%d\x05上限.", clientName, subjectname, CountKIHLimit);//聊天窗提示.
					}
				}
			}
			else
			{
				PrintToChatAll("\x04[提示]\x03%s\x05治疗了\x03%s", clientName, subjectname);//聊天窗提示.
			}
		}
	}
}

public void KIHEvent_KillInfected(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHNum == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(attacker) && GetClientTeam(attacker) == 2 && IsValidClient(client) && GetClientTeam(client) == 3)
		{
			int HLZClass = GetEntProp(client, Prop_Send, "m_zombieClass");
			
			char slName1[12];
			FormatEx(slName1, sizeof(slName1), "%N", client);
			SplitString(slName1, "Smoker", slName1, sizeof(slName1));
			
			char slName2[12];
			FormatEx(slName2, sizeof(slName2), "%N", client);
			SplitString(slName2, "Boomer", slName2, sizeof(slName2));
			
			char slName3[12];
			FormatEx(slName3, sizeof(slName3), "%N", client);
			SplitString(slName3, "Hunter", slName3, sizeof(slName3));
			
			char slName4[12];
			FormatEx(slName4, sizeof(slName4), "%N", client);
			SplitString(slName4, "Spitter", slName4, sizeof(slName4));
			
			char slName5[12];
			FormatEx(slName5, sizeof(slName5), "%N", client);
			SplitString(slName5, "Jockey", slName5, sizeof(slName5));
			
			char slName6[12];
			FormatEx(slName6, sizeof(slName6), "%N", client);
			SplitString(slName6, "Charger", slName6, sizeof(slName6));
			
			if (HLZClass == 8)
				return;
			
			if (!HLReturnset)
			{
				if (CountKIHNumoff == 0)
					return;
				
				switch (HLZClass)
				{
					case 1: //smoker
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03舌头%s.", slName1);//聊天窗提示.
					}
					case 2: //boomer
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03胖子%s.", slName2);//聊天窗提示.
					}
					case 3: //hunter
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猎人%s.", slName3);//聊天窗提示.
					}
					case 4: //spitter
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03口水%s.", slName4);//聊天窗提示.
					}
					case 5: //jockey
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猴子%s.", slName5);//聊天窗提示.
					}
					case 6: //charger
					{
						PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03牛%s.", slName6);//聊天窗提示.
					}
				}
			}
			else
			{
				if (IsPlayerAlive(attacker))
				{
					if (GetEntProp(attacker, Prop_Send, "m_isIncapacitated") == 0)
					{
						int Attackerhealth = GetClientHealth(attacker);
						int tmphealth = L4D_GetPlayerTempHealth(attacker);
					
						if (tmphealth == -1)
						{
							tmphealth = 0;
						}
						if (Attackerhealth + tmphealth + CountKIHNum > CountKIHLimit)
						{
							float overhealth,fakehealth;
							overhealth = float(Attackerhealth + tmphealth + CountKIHNum - CountKIHLimit);
							if (tmphealth < overhealth)
							{
								fakehealth = 0.0;
							}
							else
							{
								fakehealth = float(tmphealth) - overhealth;
							}
							SetEntPropFloat(attacker, Prop_Send, "m_healthBufferTime", GetGameTime());
							SetEntPropFloat(attacker, Prop_Send, "m_healthBuffer", fakehealth);
						}
							
						if ((Attackerhealth + CountKIHNum) < CountKIHLimit)
						{
							SetEntProp(attacker, Prop_Send, "m_iHealth", Attackerhealth + CountKIHNum, 1);
						}
						else
						{
							SetEntProp(attacker, Prop_Send, "m_iHealth", CountKIHLimit, 1);
						}
						
						if (CountKIHNumoff == 0)
							return;
							
						int Attackerhealth2 = Attackerhealth + tmphealth;
						
						if (Attackerhealth2 < CountKIHLimit)
						{
							switch (HLZClass)
							{
								case 1: //smoker
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03舌头%s\x04,\x05奖励\x03%d\x05点血量.", slName1, CountKIHNum);//聊天窗提示.
								}
								case 2: //boomer
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03胖子%s\x04,\x05奖励\x03%d\x05点血量.", slName2, CountKIHNum);//聊天窗提示.
								}
								case 3: //hunter
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猎人%s\x04,\x05奖励\x03%d\x05点血量.", slName3, CountKIHNum);//聊天窗提示.
								}
								case 4: //spitter
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03口水%s\x04,\x05奖励\x03%d\x05点血量.", slName4, CountKIHNum);//聊天窗提示.
								}
								case 5: //jockey
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猴子%s\x04,\x05奖励\x03%d\x05点血量.", slName5, CountKIHNum);//聊天窗提示.
								}
								case 6: //charger
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03牛%s\x04,\x05奖励\x03%d\x05点血量.", slName6, CountKIHNum);//聊天窗提示.
								}
							}
						}
						else
						{
							switch (HLZClass)
							{
								case 1: //smoker
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03舌头%s\x04,\x05血量已达\x03%d\x05上限.", slName1, CountKIHLimit);//聊天窗提示.
								}
								case 2: //boomer
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03胖子%s\x04,\x05血量已达\x03%d\x05上限.", slName2, CountKIHLimit);//聊天窗提示.
								}
								case 3: //hunter
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猎人%s\x04,\x05血量已达\x03%d\x05上限.", slName3, CountKIHLimit);//聊天窗提示.
								}
								case 4: //spitter
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03口水%s\x04,\x05血量已达\x03%d\x05上限.", slName4, CountKIHLimit);//聊天窗提示.
								}
								case 5: //jockey
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猴子%s\x04,\x05血量已达\x03%d\x05上限.", slName5, CountKIHLimit);//聊天窗提示.
								}
								case 6: //charger
								{
									PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03牛%s\x04,\x05血量已达\x03%d\x05上限.", slName6, CountKIHLimit);//聊天窗提示.
								}
							}
						}
					}
					else
					{
						if (CountKIHNumoff == 0)
							return;

						switch (HLZClass)
						{
							case 1: //smoker
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03舌头%s.", slName1);//聊天窗提示.
							}
							case 2: //boomer
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03胖子%s.", slName2);//聊天窗提示.
							}
							case 3: //hunter
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猎人%s.", slName3);//聊天窗提示.
							}
							case 4: //spitter
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03口水%s.", slName4);//聊天窗提示.
							}
							case 5: //jockey
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猴子%s.", slName5);//聊天窗提示.
							}
							case 6: //charger
							{
								PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03牛%s.", slName6);//聊天窗提示.
							}
						}
					}
				}
				else
				{
					if (CountKIHNumoff == 0)
						return;

					switch (HLZClass)
					{
						case 1: //smoker
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03舌头%s.", slName1);//聊天窗提示.
						}
						case 2: //boomer
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03胖子%s.", slName2);//聊天窗提示.
						}
						case 3: //hunter
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猎人%s.", slName3);//聊天窗提示.
						}
						case 4: //spitter
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03口水%s.", slName4);//聊天窗提示.
						}
						case 5: //jockey
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03猴子%s.", slName5);//聊天窗提示.
						}
						case 6: //charger
						{
							PrintToChat(attacker, "\x04[提示]\x05击杀感染者\x03牛%s.", slName6);//聊天窗提示.
						}
					}
				}
			}
		}
	}
}

public void KIHEvent_revive(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int subject = GetClientOfUserId(event.GetInt("subject"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHurevive == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(client) && GetClientTeam(client) == 2 && IsValidClient(subject) && GetClientTeam(subject) == 2)
		{
			char subjectname[32];
			GetTrueName(client, clientName);
			GetTrueName(subject, subjectname);
			
			if (client == subject)
			{
				PrintToChatAll("\x04[提示]\x03%s\x05救起了自己.", clientName);//聊天窗提示.
				return;
			}
			if (HLReturnset)
			{
				if (IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated") == 0)
				{
					int Attackerhealth = GetClientHealth(client);
					int tmphealth = L4D_GetPlayerTempHealth(client);
					
					if (tmphealth == -1)
					{
						tmphealth = 0;
					}
						
					if (Attackerhealth + tmphealth + CountKIHurevive > CountKIHLimit)
					{
						float overhealth,fakehealth;
						overhealth = float(Attackerhealth + tmphealth + CountKIHurevive - CountKIHLimit);
						if (tmphealth < overhealth)
						{
							fakehealth = 0.0;
						}
						else
						{
							fakehealth = float(tmphealth) - overhealth;
						}
						SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
						SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fakehealth);
					}
					if ((Attackerhealth + CountKIHurevive) < CountKIHLimit)
					{
						SetEntProp(client, Prop_Send, "m_iHealth", Attackerhealth + CountKIHurevive, 1);
					}
					else
					{
						SetEntProp(client, Prop_Send, "m_iHealth", CountKIHLimit, 1);
					}
						
					int Attackerhealth2 = Attackerhealth + tmphealth;
					
					if (Attackerhealth2 < CountKIHLimit)
					{
						PrintToChatAll("\x04[提示]\x03%s\x05救起了\x03%s\x04,\x05奖励\x03%d\x05点血量.", clientName, subjectname, CountKIHurevive);//聊天窗提示.
					}
					else
					{
						PrintToChatAll("\x04[提示]\x03%s\x05救起了\x03%s\x04,\x05血量已达\x03%d\x05上限.", clientName, subjectname, CountKIHLimit);//聊天窗提示.
					}
				}
			}
			else
			{
				PrintToChatAll("\x04[提示]\x03%s\x05救起了\x03%s", clientName, subjectname);//聊天窗提示.
			}
		}
	}
}

//幸存者在营救门复活.
public void evtSurvivorRescued(Event event, const char[] name, bool dontBroadcast)
{
	int rescuer = GetClientOfUserId(event.GetInt("rescuer"));
	int client = GetClientOfUserId(event.GetInt("victim"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHrescued == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(rescuer) && GetClientTeam(rescuer) == 2 && IsValidClient(client) && GetClientTeam(client) == 2)
		{
			char rescuername[32];
			GetTrueName(client, clientName);
			GetTrueName(rescuer, rescuername);
			if (client == rescuer)
			{
				PrintToChatAll("\x04[提示]\x03%s\x05营救了自己.", rescuername);//聊天窗提示.
				return;
			}
			if (HLReturnset)
			{
				if (IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated") == 0)
				{
					int Attackerhealth = GetClientHealth(rescuer);
					int tmphealth = L4D_GetPlayerTempHealth(rescuer);
					
					if (tmphealth == -1)
					{
						tmphealth = 0;
					}
						
					if (Attackerhealth + tmphealth + CountKIHrescued > CountKIHLimit)
					{
						float overhealth,fakehealth;
						overhealth = float(Attackerhealth + tmphealth + CountKIHrescued - CountKIHLimit);
						if (tmphealth < overhealth)
						{
							fakehealth = 0.0;
						}
						else
						{
							fakehealth = float(tmphealth) - overhealth;
						}
						SetEntPropFloat(rescuer, Prop_Send, "m_healthBufferTime", GetGameTime());
						SetEntPropFloat(rescuer, Prop_Send, "m_healthBuffer", fakehealth);
					}
					if ((Attackerhealth + CountKIHrescued) < CountKIHLimit)
					{
						SetEntProp(rescuer, Prop_Send, "m_iHealth", Attackerhealth + CountKIHrescued, 1);
					}
					else
					{
						SetEntProp(rescuer, Prop_Send, "m_iHealth", CountKIHLimit, 1);
					}
					
					int Attackerhealth2 = Attackerhealth + tmphealth;
					
					if (Attackerhealth2 < CountKIHLimit)
					{
						PrintToChatAll("\x04[提示]\x03%s\x05营救了\x03%s\x04,\x05奖励\x03%d\x05点血量.", rescuername, clientName, CountKIHrescued);//聊天窗提示.
					}
					else
					{
						PrintToChatAll("\x04[提示]\x03%s\x05营救了\x03%s\x04,\x05血量已达\x03%d\x05上限.", rescuername, clientName, CountKIHLimit);//聊天窗提示.
					}
				}
			}
			else
			{
				PrintToChatAll("\x04[提示]\x03%s\x05营救了\x03%s", rescuername, clientName);//聊天窗提示.
			}
		}
	}
}

public void Event_defibrillatorused(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int subject = GetClientOfUserId(event.GetInt("subject"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHused == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(client) && GetClientTeam(client) == 2 && IsValidClient(subject) && GetClientTeam(subject) == 2)
		{
			char subjectname[32];
			GetTrueName(client, clientName);
			GetTrueName(subject, subjectname);
			if (client == subject)
			{
				PrintToChatAll("\x04[提示]\x03%s\x05救活了自己.", clientName);//聊天窗提示.
				return;
			}
			if (HLReturnset)
			{	
				if (IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated") == 0)
				{
					int Attackerhealth = GetClientHealth(client);
					int tmphealth = L4D_GetPlayerTempHealth(client);
					
					if (tmphealth == -1)
					{
						tmphealth = 0;
					}
						
					if (Attackerhealth + tmphealth + CountKIHused > CountKIHLimit)
					{
						float overhealth,fakehealth;
						overhealth = float(Attackerhealth + tmphealth + CountKIHused - CountKIHLimit);
						if (tmphealth < overhealth)
						{
							fakehealth = 0.0;
						}
						else
						{
							fakehealth = float(tmphealth) - overhealth;
						}
						SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
						SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fakehealth);
					}
					if ((Attackerhealth + CountKIHused) < CountKIHLimit)
					{
						SetEntProp(client, Prop_Send, "m_iHealth", Attackerhealth + CountKIHused, 1);
					}
					else
					{
						SetEntProp(client, Prop_Send, "m_iHealth", CountKIHLimit, 1);
					}
					
					int Attackerhealth2 = Attackerhealth + tmphealth;
					
					if (Attackerhealth2 < CountKIHLimit)
					{
						PrintToChatAll("\x04[提示]\x03%s\x05救活了\x03%s\x04,\x05奖励\x03%d\x05点血量.", clientName, subjectname, CountKIHused);//聊天窗提示.
					}
					else
					{
						PrintToChatAll("\x04[提示]\x03%s\x05救活了\x03%s\x04,\x05血量已达\x03%d\x05上限.", clientName, subjectname, CountKIHLimit);//聊天窗提示.
					}
				}
			}
			else
			{
				PrintToChatAll("\x04[提示]\x03%s\x05救活了\x03%s", clientName, subjectname);//聊天窗提示.
			}
		}
	}
}

public void KIHEvent_KillTank(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHTank == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(attacker) && GetClientTeam(attacker) == 2)
		{
			char attackername[32];
			GetTrueName(attacker, attackername);
			char slName8[8];
			FormatEx(slName8, sizeof(slName8), "%N", client);
			SplitString(slName8, "Tank", slName8, sizeof(slName8));
			
			if (HLReturnset)
			{
				if (IsPlayerAlive(client) || GetEntProp(client, Prop_Send, "m_isIncapacitated") == 0)
				{
					int Attackerhealth = GetClientHealth(attacker);
					int tmphealth = L4D_GetPlayerTempHealth(attacker);
					
					if (tmphealth == -1)
					{
						tmphealth = 0;
					}
						
					if (Attackerhealth + tmphealth + CountKIHTank > CountKIHLimit)
					{
						float overhealth,fakehealth;
						overhealth = float(Attackerhealth + tmphealth + CountKIHTank - CountKIHLimit);
						if (tmphealth < overhealth)
						{
							fakehealth = 0.0;
						}
						else
						{
							fakehealth = float(tmphealth) - overhealth;
						}
						SetEntPropFloat(attacker, Prop_Send, "m_healthBufferTime", GetGameTime());
						SetEntPropFloat(attacker, Prop_Send, "m_healthBuffer", fakehealth);
					}
					if ((Attackerhealth + CountKIHTank) < CountKIHLimit)
					{
						SetEntProp(attacker, Prop_Send, "m_iHealth", Attackerhealth + CountKIHTank, 1);
					}
					else
					{
						SetEntProp(attacker, Prop_Send, "m_iHealth", CountKIHLimit, 1);
					}
					
					int Attackerhealth2 = Attackerhealth + tmphealth;
					
					if (Attackerhealth2 < CountKIHLimit)
					{
						PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03坦克%s\x04,\x05奖励\x03%d\x05点血量.", attackername, slName8, CountKIHTank);
					}
					else
					{
						PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03坦克%s\x04,\x05血量已达\x03%d\x05上限.", attackername, slName8, CountKIHLimit);//聊天窗提示.
					}
				}
			}
			else
			{
				PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03坦克%s\x05.", attackername, slName8);//聊天窗提示.
			}
		}
	}
}

public void KIHEvent_KillWitch(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int Crownd   = GetEventBool(event,"oneshot");
	
	if (CountKIHenabled == 0)
		return;
		
	if (CountKIHenabled == 1 && l4d2_HLReturnset)
	{
		if(IsValidClient(client) && GetClientTeam(client) == 2)
		{
			GetTrueName(client, clientName);
			
			if (IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated") == 0)
			{
				switch (Crownd)
				{
					case 0:
					{
						if (CountKIHWitch == 0)
							return;
						
						if (HLReturnset)
						{
							
							int Attackerhealth = GetClientHealth(client);
							int tmphealth = L4D_GetPlayerTempHealth(client);
							
							if (tmphealth == -1)
							{
								tmphealth = 0;
							}
						
							if (Attackerhealth + tmphealth + CountKIHWitch > CountKIHLimit)
							{
								float overhealth,fakehealth;
								overhealth = float(Attackerhealth + tmphealth + CountKIHWitch - CountKIHLimit);
								if (tmphealth < overhealth)
								{
									fakehealth = 0.0;
								}
								else
								{
									fakehealth = float(tmphealth) - overhealth;
								}
								SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
								SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fakehealth);
							}
							if ((Attackerhealth + CountKIHWitch) < CountKIHLimit)
							{
								SetEntProp(client, Prop_Send, "m_iHealth", Attackerhealth + CountKIHWitch, 1);
							}
							else
							{
								SetEntProp(client, Prop_Send, "m_iHealth", CountKIHLimit, 1);
							}
							
							int Attackerhealth2 = Attackerhealth + tmphealth;
						
							if (Attackerhealth2 < CountKIHLimit)
							{
								PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03女巫\x04,\x05奖励\x03%d\x05点血量.", clientName, CountKIHWitch);
							}
							else
							{
								PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03女巫\x04,\x05血量已达\x03%d\x05上限.", clientName, CountKIHLimit);//聊天窗提示.
							}
						}
						else
						{
							PrintToChatAll("\x04[提示]\x03%s\x05击杀了\x03女巫\x05.", clientName);//聊天窗提示.
						}
					}
					case 1:
					{
						if (CountKIHWitchIsHeadshot == 0)
							return;
						
						if (HLReturnset)
						{
							int Attackerhealth = GetClientHealth(client);
							int tmphealth = L4D_GetPlayerTempHealth(client);
							
							if (tmphealth == -1)
							{
								tmphealth = 0;
							}
						
							if (Attackerhealth + tmphealth + CountKIHWitchIsHeadshot > CountKIHLimit)
							{
								float overhealth,fakehealth;
								overhealth = float(Attackerhealth + tmphealth + CountKIHWitchIsHeadshot - CountKIHLimit);
								if (tmphealth < overhealth)
								{
									fakehealth = 0.0;
								}
								else
								{
									fakehealth = float(tmphealth) - overhealth;
								}
								SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
								SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fakehealth);
							}
							if ((Attackerhealth + CountKIHWitchIsHeadshot) < CountKIHLimit)
							{
								SetEntProp(client, Prop_Send, "m_iHealth", Attackerhealth + CountKIHWitchIsHeadshot, 1);
							}
							else
							{
								SetEntProp(client, Prop_Send, "m_iHealth", CountKIHLimit, 1);
							}

							int Attackerhealth2 = Attackerhealth + tmphealth;
						
							if (Attackerhealth2 < CountKIHLimit)
							{
								PrintToChatAll("\x04[提示]\x03%s\x05奋力一击\x04,\x05秒杀了\x03女巫\x04,\x05奖励\x03%d\x05点血量.", clientName, CountKIHWitchIsHeadshot);
							}
							else
							{
								PrintToChatAll("\x04[提示]\x03%s\x05奋力一击\x04,\x05秒杀了女巫\x04,\x05血量已达\x03%d\x05上限.", clientName, CountKIHLimit);//聊天窗提示.
							}
						}
						else
						{
							PrintToChatAll("\x04[提示]\x03%s\x05奋力一击\x04,\x05秒杀了女巫.", clientName);//聊天窗提示.
						}
					}
				}
			}
		}
	}
}

int L4D_GetPlayerTempHealth(int client)
{
    static Handle painPillsDecayCvar = null;
    if (painPillsDecayCvar == null)
    {
        painPillsDecayCvar = FindConVar("pain_pills_decay_rate");
        if (painPillsDecayCvar == null)
        {
            return -1;
        }
    }

    int tempHealth = RoundToCeil(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(painPillsDecayCvar))) - 1;
    return tempHealth < 0 ? 0 : tempHealth;
}

bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

int GetTrueName(int bot, char[] savename)
{
	int tbot = IsClientIdle(bot);
	if(tbot != 0)
	{
		Format(savename, 32, "★闲置:%N★", tbot);
	}
	else
	{
		GetClientName(bot, savename, 32);
	}
}

int IsClientIdle(int bot)
{
	if(IsClientInGame(bot) && GetClientTeam(bot) == 2 && IsFakeClient(bot))
	{
		char sNetClass[12];
		GetEntityNetClass(bot, sNetClass, sizeof(sNetClass));

		if(strcmp(sNetClass, "SurvivorBot") == 0)
		{
			int client = GetClientOfUserId(GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID"));			
			if(client > 0 && IsClientInGame(client))
			{
				return client;
			}
		}
	}
	return 0;
}
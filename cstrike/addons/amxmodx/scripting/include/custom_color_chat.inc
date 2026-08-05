#if defined _custom_color_chat_included
	#endinput
#endif
#define _custom_color_chat_included

#pragma library "custom_color_chat"

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#else
#define Red print_team_red
#define Blue print_team_blue
#endif

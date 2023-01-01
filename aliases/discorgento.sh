#!/bin/bash

dg-splash-screen() {
  local DG='#f16323'
  local DI='#7389dc'
  local IN='#c13584'
  local SP='#1ed760'
  local TW='#1d9bf0'
  local YT='#f00'

  gum format -t template << EOL

            {{ Foreground "$DG" ".:-==========-:." }}              {{ Foreground "$DG" (Bold "DISCORGENTO") }} · {{ Underline "https://discorgento.com" }}
        {{ Foreground "$DG" ".:==-:.." }}         {{ Foreground "$DG" ".:-=-:." }}          {{ Italic "M2 development made" }} {{ CrossOut (Italic "easy") }} {{ Italic "less painful" }}
      {{ Foreground "$DG" ":==:." }}                 {{ Foreground "$DG" ".:-==:" }}        
    {{ Foreground "$DG" ".==." }}                -@@@@@% {{ Foreground "$DG" ".==." }}      {{ Foreground "$DI" "Discord" }}
   {{ Foreground "$DG" "-+:" }}                  -@@@@@@   {{ Foreground "$DG" ":+-" }}     {{ Underline "https://discord.io/Discorgento" }}
  {{ Foreground "$DG" "==" }}                    -@@@@@%     {{ Foreground "$DG" "==" }}    
 {{ Foreground "$DG" "-+" }}           .-+*#%%#*+*@@@@@%      {{ Foreground "$DG" "+-" }}   GitHub:
{{ Foreground "$DG" ".+:" }}         -#@@@@@@@@@@@@@@@@%      {{ Foreground "$DG" ":+." }}  {{ Underline "https://github.com/discorgento" }}
{{ Foreground "$DG" "==" }}        .#@@@@@@@@@@@@@@@@@@%       {{ Foreground "$DG" "==" }}  
{{ Foreground "$DG" "+-" }}       .@@@@@@@*=--=*@@@@@@@%       {{ Foreground "$DG" "-+" }}  {{ Foreground "$IN" "Instagram" }}
{{ Foreground "$DG" "+-" }}       *@@@@@%.      .%@@@@@%       {{ Foreground "$DG" "-+" }}  {{ Underline "https://instagram.com/discorgento" }}
{{ Foreground "$DG" "==" }}       %@@@@@-        -@@@@@%       {{ Foreground "$DG" "==" }}  
{{ Foreground "$DG" ".+:" }}      #@@@@@#        #@@@@@#      {{ Foreground "$DG" ":+." }}  {{ Foreground "$SP" "Spotify" }}
 {{ Foreground "$DG" "-+" }}      :@@@@@@%=:..:=%@@@@@@:      {{ Foreground "$DG" "+-" }}   {{ Underline "https://sptlnk.com/discorgento" }}
  {{ Foreground "$DG" "==" }}      -@@@@@@@@@@@@@@@@@@-      {{ Foreground "$DG" "==" }}    
   {{ Foreground "$DG" "-+:" }}     .+@@@@@@@@@@@@@@+.     {{ Foreground "$DG" ":+-" }}     {{ Foreground "$TW" "Twitter" }}
    {{ Foreground "$DG" ".==." }}      -*#%@@@@%#*-      {{ Foreground "$DG" ".==." }}      {{ Underline "https://twitter.com/discorgento" }}
      {{ Foreground "$DG" ":==:." }}                  {{ Foreground "$DG" ".:==:" }}        
        {{ Foreground "$DG" ".:==-:.." }}        {{ Foreground "$DG" "..:-==:." }}          {{ Foreground "$YT" "YouTube" }}
            {{ Foreground "$DG" ".:-==========-:." }}              {{ Underline "https://youtube.com/@discorgento" }}

EOL
}
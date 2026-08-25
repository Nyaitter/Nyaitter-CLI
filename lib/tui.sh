#!/usr/bin/env bash
# ==============================================================================
# Nyaitter CLI - TUI (Terminal User Interface) 超高速フル機能クライアント
# ==============================================================================

run_tui() {
  # 画面バッファ退避 & カーソル非表示
  tput smcup
  tput civis
  tput clear
  stty -echo

  # 終了時のクリーンアップ
  cleanup_tui() {
    tput rmcup
    tput cnorm
    stty echo
    exit 0
  }
  trap cleanup_tui SIGINT SIGTERM EXIT

  local current_tab=1 # 1:Home, 2:Trend/Search, 3:Notif, 4:DM, 5:Profile, 6:Settings
  local home_subtab="foryou" # foryou / following
  local selected_idx=0
  local scroll_offset=0
  local toast_msg=""
  local search_query=""

  # キャッシュデータ (TSV 配列: パース済み)
  local -a cached_items=()
  local cached_count=0

  # プロフィールキャッシュ
  local prof_name="" prof_handle="" prof_id="" prof_bio="" prof_fc="0" prof_flc="0" prof_pc="0"
  local my_name="ゲスト" my_handle="未ログイン" my_id=""

  # ── ユーザー情報更新 ──────────────────────────────────────────────────────────
  refresh_user_info() {
    if [ -n "$NYAITTER_TOKEN" ]; then
      local me_json
      me_json=$(api_request GET "/auth/me" 2>/dev/null || echo "{}")
      IFS=$'\t' read -r my_name my_handle my_id <<< "$(echo "$me_json" | jq -r '
        [(.user.name // .name // "ログイン済ユーザー"), (.user.nyaitter_id // ("#" + (.user.id|tostring)) // "@user"), (.user.id // "")] | @tsv
      ' 2>/dev/null || echo -e "ユーザー\t@user\t")"
    else
      my_name="ゲスト"
      my_handle="未ログイン"
      my_id=""
    fi
  }

  # ── データ取得 & 単一パス一括パース ──────────────────────────────────────────
  fetch_current_tab_data() {
    toast_msg="📡 読み込み中..."
    selected_idx=0
    scroll_offset=0
    cached_items=()
    cached_count=0

    case "$current_tab" in
      1) # ホームタイムライン
        local raw_json
        raw_json=$(api_request GET "/posts/page?mode=timeline&tab=${home_subtab}&limit=40" 2>/dev/null || echo "{}")
        mapfile -t cached_items < <(echo "$raw_json" | jq -r '
          (.posts // .)[] |
          [
            (.id // ""),
            ((.user.name // .author.name // "No Name") | gsub("[\t\n]"; " ")),
            ((.user.nyaitter_id // .author.nyaitter_id // ("#" + (.userid // .id | tostring))) | gsub("[\t\n]"; " ")),
            ((.content // "") | gsub("[\t\n]"; " ")),
            (.like_count // .likesCount // 0),
            (.repost_count // .repostsCount // 0),
            (.reply_count // .repliesCount // 0),
            ((.created_at // .createdAt // "") | split("T")[1] | split(".")[0] // "")
          ] | @tsv
        ' 2>/dev/null || true)
        cached_count="${#cached_items[@]}"
        ;;

      2) # トレンド / 検索
        local raw_json
        if [ -n "$search_query" ]; then
          local enc_q
          enc_q=$(jq -rn --arg x "$search_query" '$x|@uri')
          raw_json=$(api_request GET "/posts/search?q=${enc_q}&limit=40" 2>/dev/null || echo "{}")
        else
          raw_json=$(api_request GET "/posts/trending?limit=40" 2>/dev/null || echo "{}")
        fi
        mapfile -t cached_items < <(echo "$raw_json" | jq -r '
          (.posts // .)[] |
          [
            (.id // ""),
            ((.user.name // .author.name // "No Name") | gsub("[\t\n]"; " ")),
            ((.user.nyaitter_id // .author.nyaitter_id // ("#" + (.userid // .id | tostring))) | gsub("[\t\n]"; " ")),
            ((.content // "") | gsub("[\t\n]"; " ")),
            (.like_count // .likesCount // 0),
            (.repost_count // .repostsCount // 0),
            (.reply_count // .repliesCount // 0),
            ((.created_at // .createdAt // "") | split("T")[1] | split(".")[0] // "")
          ] | @tsv
        ' 2>/dev/null || true)
        cached_count="${#cached_items[@]}"
        ;;

      3) # 通知
        local raw_json
        raw_json=$(api_request GET "/notifications?limit=40" 2>/dev/null || echo "{}")
        mapfile -t cached_items < <(echo "$raw_json" | jq -r '
          (.notifications // .)[] |
          [
            (.id // ""),
            ((.type // "") | gsub("[\t\n]"; " ")),
            ((.actor.name // .actor.username // "誰か") | gsub("[\t\n]"; " ")),
            ((.message // "") | gsub("[\t\n]"; " ")),
            ((.created_at // .createdAt // "") | split("T")[1] | split(".")[0] // "")
          ] | @tsv
        ' 2>/dev/null || true)
        cached_count="${#cached_items[@]}"
        ;;

      4) # DM
        local raw_json
        raw_json=$(api_request GET "/dm" 2>/dev/null || echo "{}")
        mapfile -t cached_items < <(echo "$raw_json" | jq -r '
          (.channels // .)[] |
          [
            (.id // ""),
            ((.name // .targetUser.name // "DMスレッド") | gsub("[\t\n]"; " "))
          ] | @tsv
        ' 2>/dev/null || true)
        cached_count="${#cached_items[@]}"
        ;;

      5) # マイページ
        if [ -n "$my_id" ]; then
          local raw_prof raw_posts
          raw_prof=$(api_request GET "/users/${my_id}" 2>/dev/null || echo "{}")
          raw_posts=$(api_request GET "/posts/user/${my_id}?limit=30" 2>/dev/null || echo "{}")

          IFS=$'\t' read -r prof_name prof_handle prof_id prof_bio prof_fc prof_flc prof_pc <<< "$(echo "$raw_prof" | jq -r '
            .user | [
              (.name // "No Name"),
              (.nyaitter_id // ("#" + (.id|tostring))),
              (.id // ""),
              ((.me // .bio // "なし") | gsub("[\t\n]"; " ")),
              (.following_count // 0),
              (.follower_count // 0),
              (.post_count // 0)
            ] | @tsv
          ' 2>/dev/null || echo -e "No Name\t#0\t0\tなし\t0\t0\t0")"

          mapfile -t cached_items < <(echo "$raw_posts" | jq -r '
            (.posts // .)[] |
            [
              (.id // ""),
              ((.user.name // .author.name // "No Name") | gsub("[\t\n]"; " ")),
              ((.user.nyaitter_id // .author.nyaitter_id // ("#" + (.userid // .id | tostring))) | gsub("[\t\n]"; " ")),
              ((.content // "") | gsub("[\t\n]"; " ")),
              (.like_count // .likesCount // 0),
              (.repost_count // .repostsCount // 0),
              (.reply_count // .repliesCount // 0),
              ((.created_at // .createdAt // "") | split("T")[1] | split(".")[0] // "")
            ] | @tsv
          ' 2>/dev/null || true)
          cached_count="${#cached_items[@]}"
        fi
        ;;

      6) # 設定
        ;;
    esac
    toast_msg=""
    tput clear
  }

  # 初期読み込み
  refresh_user_info
  fetch_current_tab_data

  # ── メイン高速描画ループ ─────────────────────────────────────────────────────
  while true; do
    local rows cols
    rows=$(tput lines)
    cols=$(tput cols)

    # バッファ変数
    local out=""
    local line=""

    # ── 1. タブバー & ユーザーヘッダー ──────────────────────────────────────
    local tab1=" [1] ホーム " tab2=" [2] トレンド " tab3=" [3] 通知 "
    local tab4=" [4] DM " tab5=" [5] マイページ " tab6=" [6] 設定 "

    [ "$current_tab" -eq 1 ] && tab1="\033[7;1;32m${tab1}\033[0m\033[7;1;36m"
    [ "$current_tab" -eq 2 ] && tab2="\033[7;1;32m${tab2}\033[0m\033[7;1;36m"
    [ "$current_tab" -eq 3 ] && tab3="\033[7;1;32m${tab3}\033[0m\033[7;1;36m"
    [ "$current_tab" -eq 4 ] && tab4="\033[7;1;32m${tab4}\033[0m\033[7;1;36m"
    [ "$current_tab" -eq 5 ] && tab5="\033[7;1;32m${tab5}\033[0m\033[7;1;36m"
    [ "$current_tab" -eq 6 ] && tab6="\033[7;1;32m${tab6}\033[0m\033[7;1;36m"

    printf -v line "\033[H\033[7;1;36m🐾 Nyaitter TUI |%b%b%b%b%b%b\033[7;1;36m | 👤 %s (%s) \033[0m\033[K" \
      "$tab1" "$tab2" "$tab3" "$tab4" "$tab5" "$tab6" "$my_name" "$my_handle"
    out+="${line}"$'\n'

    # サブヘッダー
    if [ "$current_tab" -eq 1 ]; then
      local sub_txt=" [Tab] 切り替え: おすすめ (For You) / フォロー中 (Following) -> 現在: ${home_subtab} "
      printf -v line "\033[1;30;46m%-*s\033[0m\033[K" "$cols" "$sub_txt"
    elif [ "$current_tab" -eq 2 ]; then
      local sub_txt=" [/] 検索ワード: ${search_query:-'(なし: トレンド一覧表示中)'} "
      printf -v line "\033[1;30;46m%-*s\033[0m\033[K" "$cols" "$sub_txt"
    else
      printf -v line "\033[1;30;46m%-*s\033[0m\033[K" "$cols" " [q]終了 [r]更新 [p]投稿 [L]ログイン [?]ヘルプ "
    fi
    out+="${line}"$'\n'

    # ── 2. メイン描画領域 ──────────────────────────────────────────────────
    local list_height=$((rows - 5))
    if [ "$list_height" -lt 5 ]; then list_height=5; fi
    local rendered_lines=0

    case "$current_tab" in
      1|2) # タイムライン / トレンド / 検索
        if [ "$selected_idx" -lt "$scroll_offset" ]; then
          scroll_offset="$selected_idx"
        elif [ "$selected_idx" -ge "$((scroll_offset + list_height / 3))" ]; then
          scroll_offset=$((selected_idx - list_height / 3 + 1))
        fi

        if [ "$cached_count" -gt 0 ]; then
          for ((i=0; i<cached_count; i++)); do
            if [ "$i" -lt "$scroll_offset" ]; then continue; fi
            if [ "$rendered_lines" -ge "$list_height" ]; then break; fi

            local p_id p_author p_handle p_content p_likes p_reposts p_replies p_time
            IFS=$'\t' read -r p_id p_author p_handle p_content p_likes p_reposts p_replies p_time <<< "${cached_items[i]}"

            local trunc_content="${p_content:0:$((cols - 8))}"

            if [ "$i" -eq "$selected_idx" ]; then
              printf -v line "\033[1;32m▶ \033[7;1m#%-5s %-16s (%s) %s\033[0m\033[K" "$p_id" "$p_author" "$p_handle" "$p_time"
              out+="${line}"$'\n'
              printf -v line "  \033[1m%-*s\033[0m\033[K" "$((cols - 4))" "$trunc_content"
              out+="${line}"$'\n'
              printf -v line "  \033[2;33m💬 %-3s 🔁 %-3s ❤️ %-3s\033[0m\033[K" "$p_replies" "$p_reposts" "$p_likes"
              out+="${line}"$'\n'
            else
              printf -v line "\033[36m  #%-5s\033[0m \033[1m%-16s\033[0m \033[2m(%s) %s\033[0m\033[K" "$p_id" "$p_author" "$p_handle" "$p_time"
              out+="${line}"$'\n'
              printf -v line "  %-*s\033[K" "$((cols - 4))" "$trunc_content"
              out+="${line}"$'\n'
              printf -v line "  \033[2m💬 %-3s 🔁 %-3s ❤️ %-3s\033[0m\033[K" "$p_replies" "$p_reposts" "$p_likes"
              out+="${line}"$'\n'
            fi
            rendered_lines=$((rendered_lines + 3))
          done
        else
          out+=$'\n'"  \033[2m投稿が見つかりませんでした。\033[0m\033[K"$'\n\n\033[K'$'\n'
          rendered_lines=3
        fi
        ;;

      3) # 通知
        if [ "$cached_count" -gt 0 ]; then
          for ((i=0; i<cached_count; i++)); do
            if [ "$rendered_lines" -ge "$list_height" ]; then break; fi

            local n_id n_type n_actor n_msg n_time
            IFS=$'\t' read -r n_id n_type n_actor n_msg n_time <<< "${cached_items[i]}"

            if [ "$i" -eq "$selected_idx" ]; then
              printf -v line "\033[1;32m▶ \033[7;1m#%-5s [%s] %s (%s)\033[0m\033[K" "$n_id" "$n_type" "$n_actor" "$n_time"
              out+="${line}"$'\n'
              printf -v line "  \033[1m%s\033[0m\033[K" "$n_msg"
              out+="${line}"$'\n'
            else
              printf -v line "\033[33m  #%-5s\033[0m \033[1m[%s]\033[0m %s (%s)\033[K" "$n_id" "$n_type" "$n_actor" "$n_time"
              out+="${line}"$'\n'
              printf -v line "  %s\033[K" "$n_msg"
              out+="${line}"$'\n'
            fi
            rendered_lines=$((rendered_lines + 2))
          done
        else
          out+=$'\n'"  \033[2m通知はありません。[A] で全既読化\033[0m\033[K"$'\n\n\033[K'$'\n'
          rendered_lines=3
        fi
        ;;

      4) # DM
        if [ "$cached_count" -gt 0 ]; then
          for ((i=0; i<cached_count; i++)); do
            if [ "$rendered_lines" -ge "$list_height" ]; then break; fi

            local c_id c_name
            IFS=$'\t' read -r c_id c_name <<< "${cached_items[i]}"

            if [ "$i" -eq "$selected_idx" ]; then
              printf -v line "\033[1;32m▶ \033[7;1m✉️ #%-5s %-30s [Enter] 会話を開く\033[0m\033[K" "$c_id" "$c_name"
            else
              printf -v line "  \033[36m✉️ #%-5s\033[0m %-30s\033[K" "$c_id" "$c_name"
            fi
            out+="${line}"$'\n'
            rendered_lines=$((rendered_lines + 1))
          done
        else
          out+=$'\n'"  \033[2mDM チャンネルがありません。[s] で新規DM送信\033[0m\033[K"$'\n\n\033[K'$'\n'
          rendered_lines=3
        fi
        ;;

      5) # マイページ
        if [ -n "$my_id" ]; then
          printf -v line "\033[1;36m👤 プロフィール:\033[0m \033[1m%s (%s)\033[0m [ID: #%s]\033[K" "$prof_name" "$prof_handle" "$prof_id"
          out+="${line}"$'\n'
          printf -v line "   \033[2mBio:\033[0m %s\033[K" "$prof_bio"
          out+="${line}"$'\n'
          printf -v line "   \033[2mフォロー:\033[0m %s | \033[2mフォロワー:\033[0m %s | \033[2m投稿数:\033[0m %s\033[K" "$prof_fc" "$prof_flc" "$prof_pc"
          out+="${line}"$'\n'
          printf -v line "\033[1;33m──────────────── 自分の最新投稿 ────────────────\033[0m\033[K"
          out+="${line}"$'\n'
          rendered_lines=4

          for ((i=0; i<cached_count; i++)); do
            if [ "$rendered_lines" -ge "$list_height" ]; then break; fi

            local p_id p_author p_handle p_content p_likes p_reposts p_replies p_time
            IFS=$'\t' read -r p_id p_author p_handle p_content p_likes p_reposts p_replies p_time <<< "${cached_items[i]}"

            local trunc_content="${p_content:0:$((cols - 8))}"

            if [ "$i" -eq "$selected_idx" ]; then
              printf -v line "\033[1;32m▶ \033[7;1m#%-5s %-16s (%s) %s\033[0m\033[K" "$p_id" "$p_author" "$p_handle" "$p_time"
              out+="${line}"$'\n'
              printf -v line "  \033[1m%-*s\033[0m\033[K" "$((cols - 4))" "$trunc_content"
              out+="${line}"$'\n'
              printf -v line "  \033[2;33m💬 %-3s 🔁 %-3s ❤️ %-3s\033[0m\033[K" "$p_replies" "$p_reposts" "$p_likes"
              out+="${line}"$'\n'
            else
              printf -v line "\033[36m  #%-5s\033[0m \033[1m%-16s\033[0m \033[2m(%s) %s\033[0m\033[K" "$p_id" "$p_author" "$p_handle" "$p_time"
              out+="${line}"$'\n'
              printf -v line "  %-*s\033[K" "$((cols - 4))" "$trunc_content"
              out+="${line}"$'\n'
              printf -v line "  \033[2m💬 %-3s 🔁 %-3s ❤️ %-3s\033[0m\033[K" "$p_replies" "$p_reposts" "$p_likes"
              out+="${line}"$'\n'
            fi
            rendered_lines=$((rendered_lines + 3))
          done
        else
          out+=$'\n'"  \033[1;31m⚠️ 未ログインです。\033[0m [L] キーを押してログインまたは API キーを設定してください。\033[K"$'\n\n\033[K'$'\n'
          rendered_lines=3
        fi
        ;;

      6) # 設定
        printf -v line "\033[1;36m⚙️ 設定 & 認証管理\033[0m\033[K"
        out+="${line}"$'\n\n\033[K'$'\n'
        printf -v line "  \033[1m1. Nyaitter サーバー URL:\033[0m %s\033[K" "$NYAITTER_URL"
        out+="${line}"$'\n'
        if [ -n "$NYAITTER_TOKEN" ]; then
          printf -v line "  \033[1m2. 現在のトークン:\033[0m        ***%s (\033[32m認証済: %s\033[0m)\033[K" "${NYAITTER_TOKEN: -4}" "$my_name"
        else
          printf -v line "  \033[1m2. 現在のトークン:\033[0m        \033[31m未設定 (ゲスト)\033[0m\033[K"
        fi
        out+="${line}"$'\n\n'
        printf -v line "\033[1;33m  [操作キー]:\033[0m\033[K"
        out+="${line}"$'\n'
        printf -v line "    \033[36m[k]\033[0m API キー / Bot トークンでログイン\033[K"
        out+="${line}"$'\n'
        printf -v line "    \033[36m[u]\033[0m Nyaitter サーバー URL を変更\033[K"
        out+="${line}"$'\n'
        printf -v line "    \033[36m[o]\033[0m ログアウト (トークン消去)\033[K"
        out+="${line}"$'\n'
        rendered_lines=10
        ;;
    esac

    # 余白パディング（行末クリアを伴う）
    while [ "$rendered_lines" -lt "$list_height" ]; do
      out+=$'\033[K\n'
      rendered_lines=$((rendered_lines + 1))
    done

    # ── 3. フッター / ステータスバー ────────────────────────────────────────
    if [ -n "$toast_msg" ]; then
      printf -v line "\033[%d;1H\033[1;33m📢 %-*s\033[0m\033[K" "$((rows - 2))" "$((cols - 4))" "$toast_msg"
    else
      printf -v line "\033[%d;1H\033[2m[1-6]タブ [j/k/↑/↓]移動 [Enter]詳細 [p]投稿 [c]返信 [l]いいね [t]リポスト [L]ログイン [?]ヘルプ\033[0m\033[K" "$((rows - 2))"
    fi
    out+="${line}"$'\n'

    # 画面へ一括出力（改行損失ゼロ）
    printf "%s" "$out"

    # ── 4. キー入力処理 ───────────────────────────────────────────────────
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 rest || true
      key+="$rest"
    fi

    case "$key" in
      q|Q) cleanup_tui ;;

      # タブ直接切り替え
      1|2|3|4|5|6)
        current_tab="$key"
        fetch_current_tab_data
        ;;

      $'\t') # Tab: サブタブ切り替え
        if [ "$current_tab" -eq 1 ]; then
          [ "$home_subtab" = "foryou" ] && home_subtab="following" || home_subtab="foryou"
          fetch_current_tab_data
        fi
        ;;

      j|$'\x1b[B') # 下移動
        if [ "$selected_idx" -lt "$((cached_count - 1))" ]; then
          selected_idx=$((selected_idx + 1))
        fi
        ;;
      k|$'\x1b[A') # 上移動
        [ "$selected_idx" -gt 0 ] && selected_idx=$((selected_idx - 1))
        ;;

      r|R) # リフレッシュ
        refresh_user_info
        fetch_current_tab_data
        toast_msg="🔄 データを更新しました"
        ;;

      # ── 検索 (/) ───────────────────────────────────────────────────────────
      /)
        tput cup $((rows - 1)) 0
        stty echo
        tput cnorm
        printf "\033[1;36m🔍 検索キーワードを入力 (クリアは空Enter):\033[0m\033[K "
        read -r search_query
        stty -echo
        tput civis
        current_tab=2
        fetch_current_tab_data
        ;;

      # ── 新規投稿 (p) ───────────────────────────────────────────────────────
      p|P)
        tput cup $((rows - 1)) 0
        stty echo
        tput cnorm
        printf "\033[1;36m📝 投稿本文を入力 (キャンセルは空Enter):\033[0m\033[K "
        read -r new_content
        stty -echo
        tput civis
        if [ -n "$new_content" ]; then
          local p_payload
          p_payload=$(jq -n --arg c "$new_content" '{ content: $c, visibility: "public" }')
          api_request POST "/posts" "$p_payload" >/dev/null 2>&1 || true
          toast_msg="✅ 新しいポストを投稿しました！"
          fetch_current_tab_data
        fi
        ;;

      # ── 返信 (c) ───────────────────────────────────────────────────────────
      c|C)
        local curr_pid=""
        if [ "$cached_count" -gt 0 ]; then
          IFS=$'\t' read -r curr_pid _ <<< "${cached_items[selected_idx]}"
        fi
        if [ -n "$curr_pid" ]; then
          tput cup $((rows - 1)) 0
          stty echo
          tput cnorm
          printf "\033[1;36m💬 #%s への返信を入力 (キャンセルは空Enter):\033[0m\033[K " "$curr_pid"
          read -r reply_content
          stty -echo
          tput civis
          if [ -n "$reply_content" ]; then
            local r_payload
            r_payload=$(jq -n --arg c "$reply_content" --argjson r "$curr_pid" '{ content: $c, visibility: "public", reply_to_id: $r }')
            api_request POST "/posts" "$r_payload" >/dev/null 2>&1 || true
            toast_msg="✅ ポスト #${curr_pid} に返信しました！"
            fetch_current_tab_data
          fi
        fi
        ;;

      # ── いいね (l) ─────────────────────────────────────────────────────────
      l|L)
        if [ "$key" = "l" ]; then
          local curr_pid=""
          if [ "$cached_count" -gt 0 ]; then
            IFS=$'\t' read -r curr_pid _ <<< "${cached_items[selected_idx]}"
          fi
          if [ -n "$curr_pid" ]; then
            api_request POST "/posts/${curr_pid}/like" >/dev/null 2>&1 || true
            toast_msg="❤️ ポスト #${curr_pid} にいいねしました！"
          fi
        else
          current_tab=6
          fetch_current_tab_data
        fi
        ;;

      # ── リポスト (t) ───────────────────────────────────────────────────────
      t|T)
        local curr_pid=""
        if [ "$cached_count" -gt 0 ]; then
          IFS=$'\t' read -r curr_pid _ <<< "${cached_items[selected_idx]}"
        fi
        if [ -n "$curr_pid" ]; then
          api_request POST "/posts/${curr_pid}/repost" >/dev/null 2>&1 || true
          toast_msg="🔁 ポスト #${curr_pid} をリポストしました！"
        fi
        ;;

      # ── 通知全既読 (A) ─────────────────────────────────────────────────────
      a|A)
        if [ "$current_tab" -eq 3 ]; then
          api_request POST "/notifications/read-all" >/dev/null 2>&1 || true
          toast_msg="✅ すべての通知を既読にしました。"
          fetch_current_tab_data
        fi
        ;;

      # ── DM送信 (s) ─────────────────────────────────────────────────────────
      s|S)
        if [ "$current_tab" -eq 4 ]; then
          tput cup $((rows - 1)) 0
          stty echo
          tput cnorm
          printf "\033[1;36m✉️ 送信先ユーザーID:\033[0m\033[K "
          read -r dm_target
          printf "\033[1;36m✉️ メッセージ本文:\033[0m\033[K "
          read -r dm_text
          stty -echo
          tput civis
          if [ -n "$dm_target" ] && [ -n "$dm_text" ]; then
            local dm_payload
            dm_payload=$(jq -n --arg msg "$dm_text" '{ content: $msg }')
            api_request POST "/dm/${dm_target}/messages" "$dm_payload" >/dev/null 2>&1 || true
            toast_msg="✉️ DMを送信しました！"
            fetch_current_tab_data
          fi
        fi
        ;;

      # ── 設定画面専用キー ───────────────────────────────────────────────────
      k|K)
        if [ "$current_tab" -eq 6 ]; then
          tput cup $((rows - 1)) 0
          stty echo
          tput cnorm
          printf "\033[1;36m🔑 API キー / Bot トークンを入力:\033[0m\033[K "
          read -r input_tok
          stty -echo
          tput civis
          if [ -n "$input_tok" ]; then
            NYAITTER_TOKEN="$input_tok"
            save_config
            refresh_user_info
            toast_msg="🔑 ログインに成功しました: ${my_name}"
            current_tab=1
            fetch_current_tab_data
          fi
        fi
        ;;

      u|U)
        if [ "$current_tab" -eq 6 ]; then
          tput cup $((rows - 1)) 0
          stty echo
          tput cnorm
          printf "\033[1;36m🌐 新しいサーバー URL:\033[0m\033[K "
          read -r input_url
          stty -echo
          tput civis
          if [ -n "$input_url" ]; then
            NYAITTER_URL="$input_url"
            save_config
            refresh_user_info
            toast_msg="🌐 サーバー URL を更新しました: ${NYAITTER_URL}"
            fetch_current_tab_data
          fi
        fi
        ;;

      o|O)
        if [ "$current_tab" -eq 6 ]; then
          NYAITTER_TOKEN=""
          save_config
          refresh_user_info
          toast_msg="🚪 ログアウトしました。"
          current_tab=1
          fetch_current_tab_data
        fi
        ;;

      # ── Enter: 詳細表示 / モーダル ──────────────────────────────────────────
      ""|$'\n')
        if [ "$current_tab" -eq 1 ] || [ "$current_tab" -eq 2 ] || [ "$current_tab" -eq 5 ]; then
          local curr_pid=""
          if [ "$cached_count" -gt 0 ]; then
            IFS=$'\t' read -r curr_pid _ <<< "${cached_items[selected_idx]}"
          fi
          if [ -n "$curr_pid" ]; then
            local full_post
            full_post=$(api_request GET "/posts/${curr_pid}" 2>/dev/null || echo "{}")
            tput clear
            tput cup 0 0
            echo -e "\033[1;36m════════════════ ポスト詳細 (#${curr_pid}) ════════════════\033[0m\n"
            echo "$full_post" | jq -r '
              (.post // .) |
              "👤 \u001b[1m\(.user.name // .author.name // "No Name")\u001b[0m \u001b[2m(\(.user.nyaitter_id // .author.nyaitter_id // ("#" + (.user.id // .author.id | tostring))))\u001b[0m\n" +
              "📅 \(.created_at // .createdAt // "")\n\n" +
              "\(.content // "")\n\n" +
              "\u001b[2m💬 \(.reply_count // .repliesCount // 0)  🔁 \(.repost_count // .repostsCount // 0)  ❤️ \(.like_count // .likesCount // 0)\u001b[0m"
            ' 2>/dev/null || echo "$full_post"
            echo -e "\n\033[1;33m[任意のキーを押して戻る]\033[0m"
            read -rsn1 _
            tput clear
          fi
        fi
        ;;

      # ── ヘルプ (?) ─────────────────────────────────────────────────────────
      \?|h|H)
        tput clear
        tput cup 0 0
        echo -e "\033[1;36m════════════════ Nyaitter TUI キーバインドヘルプ ════════════════\033[0m\n"
        echo -e "  \033[1;33m[ナビゲーション]\033[0m"
        echo -e "    1〜6       : 各タブへ切り替え (1:ホーム 2:トレンド 3:通知 4:DM 5:マイページ 6:設定)"
        echo -e "    Tab        : おすすめ (For You) / フォロー中 (Following) 切り替え"
        echo -e "    j / ↓      : 下の項目へ移動"
        echo -e "    k / ↑      : 上の項目へ移動"
        echo -e "    /          : タイムライン・トレンド内検索"
        echo -e "    Enter      : 選択中ポストの詳細表示"
        echo -e "    r          : タイムラインの手動更新 (Refresh)\n"
        echo -e "  \033[1;33m[アクション]\033[0m"
        echo -e "    p          : 新規ポストを投稿"
        echo -e "    c          : 選択中ポストに返信 (Reply)"
        echo -e "    l          : 選択中ポストにいいね (Like)"
        echo -e "    t          : 選択中ポストをリポスト (Repost)"
        echo -e "    A          : すべての通知を既読化 (通知タブ)"
        echo -e "    s          : DM メッセージ送信 (DMタブ)\n"
        echo -e "  \033[1;33m[認証・設定]\033[0m"
        echo -e "    L          : 設定・ログイン画面へジャンプ"
        echo -e "    k          : API キー / Bot トークンでログイン (設定タブ)"
        echo -e "    u          : サーバー URL の変更 (設定タブ)"
        echo -e "    o          : ログアウト (設定タブ)"
        echo -e "    q          : TUI を終了\n"
        echo -e "\033[1;33m[任意のキーを押して戻る]\033[0m"
        read -rsn1 _
        tput clear
        ;;
    esac
  done
}

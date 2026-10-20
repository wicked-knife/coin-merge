"""Build the runtime CSV from existing Chinese/English, captured text and additions.

Reference files are build inputs only; exported games load menu.*.translation.
CUSTOM columns follow EXTRA_LOCALES. Keep complete sentences and printf arguments.
"""
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRA_LOCALES = ['ru', 'ko_KR', 'ja', 'id', 'fr', 'es', 'pt', 'ar', 'zh_TW']
LOCALES = ['en_US', *EXTRA_LOCALES[:-1], 'zh_CN', 'zh_TW']
REFERENCE_KEYS = {
    '开始游戏': 'main.start_game', '挑战一下': 'main.challenge',
    '设置': 'setting.title', '提示': 'tips.title', '音效': 'setting.sound',
    '振动': 'setting.vibrate', '语言': 'setting.language',
    '返回主界面': 'setting.back_home', '返回主页': 'setting.back_home',
    '重新挑战': 'setting.retry', '发牌': 'game.deal',
    '下个目标': 'game.next_target', '解锁新槽位': 'game.unlock_slot',
    '点击解锁': 'game.unlockable', '继续合成': 'guide.keep_merge',
    '知道了': 'rank.got_it', '继续': 'game.continue_btn',
    '关卡完成！': 'game.level_clear', '合成新硬币！': 'game.level_up',
    '洗牌': 'game.shuffle', '重新开始': 'game.retry',
    '本局剩余%d次': 'game.fail_shuffle_left',
    '奖励未完成，请稍后再试': 'Video reward was not completed. Please try again.',
    'challenge.title': 'war.challenge', 'challenge.level': 'war.level_n',
    'challenge.play': 'main.start_game', 'challenge.doing': 'game.continue_btn',
    'challenge.record': 'war.time_record', 'challenge.replay': 'setting.retry',
    'challenge.tutorial_hint': 'war.guide_rules', 'challenge.wait': 'war.coming_soon',
    'challenge.available': 'war.available', 'challenge.unlock_title': 'tips.hint',
    'challenge.unlock_action': 'tips.go_merge', 'challenge.unlock_dismiss': 'tips.ok',
    'challenge.unlock_prefix': 'tips.main_merge', 'challenge.unlock_suffix': 'tips.unlock',
    'challenge.your_time': 'war.clear_time', 'challenge.best_label': 'war.best_record',
    'challenge.record_hint': 'war.try_again', 'challenge.menu_level': 'war.level_n',
    'challenge.tap_retry': 'war.tap_retry', 'challenge.back': 'war.back',
    'challenge.share': 'war.share', 'challenge.hud_level': 'war.level',
}

# Russian | Korean | Japanese | Indonesian | French | Spanish | Portuguese | Arabic | Traditional Chinese
CUSTOM = {
    '音效开关': 'Включить звук|소리 켜기/끄기|効果音の切り替え|Aktifkan suara|Activer le son|Activar sonido|Ativar som|تبديل الصوت|音效開關',
    '振动开关': 'Включить вибрацию|진동 켜기/끄기|振動の切り替え|Aktifkan getaran|Activer les vibrations|Activar vibración|Ativar vibração|تبديل الاهتزاز|震動開關',
    '关闭': 'Закрыть|닫기|閉じる|Tutup|Fermer|Cerrar|Fechar|إغلاق|關閉',
    '进入下一关': 'Следующий уровень|다음 단계|次のステージ|Level berikutnya|Niveau suivant|Siguiente nivel|Próximo nível|المستوى التالي|進入下一關',
    '奖励槽位': 'Бонусная ячейка|보너스 슬롯|ボーナス枠|Slot bonus|Case bonus|Casilla extra|Espaço extra|خانة إضافية|獎勵槽位',
    '第 %d 关 · 点击同级硬币进行整理': 'Уровень %d · Сортируйте одинаковые монеты|%d단계 · 같은 레벨의 동전을 정리하세요|ステージ %d · 同じレベルのコインを整理|Level %d · Susun koin selevel|Niveau %d · Triez les pièces identiques|Nivel %d · Ordena monedas iguales|Nível %d · Organize moedas iguais|المستوى %d · رتّب العملات المتساوية|第 %d 關 · 點擊同級硬幣進行整理',
    '点击硬币，选中顶部连续同级硬币': 'Нажмите, чтобы выбрать одинаковые монеты сверху|맨 위의 같은 레벨 동전을 선택하세요|タップして一番上の同じコインを選択|Ketuk untuk memilih koin selevel di atas|Touchez les pièces identiques du dessus|Toca para elegir las monedas iguales de arriba|Toque para selecionar moedas iguais no topo|اضغط لاختيار العملات المتساوية في الأعلى|點擊硬幣，選中頂部連續同級硬幣',
    '再点相同硬币的槽位，将它们合在一起': 'Нажмите на стопку таких же монет, чтобы переместить|같은 동전이 있는 슬롯을 눌러 옮기세요|同じコインの枠をタップして移動|Ketuk tumpukan yang cocok untuk memindahkan|Touchez une pile identique pour déplacer les pièces|Toca una pila igual para mover las monedas|Toque numa pilha igual para mover as moedas|اضغط على كومة مماثلة لنقل العملات|再點相同硬幣的槽位，將它們放在一起',
    '10 枚同级硬币，自动合成 2 枚高一级硬币': '10 одинаковых монет дают 2 монеты следующего уровня|같은 레벨 동전 10개가 한 단계 높은 동전 2개로 합쳐집니다|同じレベルの10枚が1レベル上の2枚に合成|10 koin selevel menjadi 2 koin satu level lebih tinggi|10 pièces identiques donnent 2 pièces de niveau supérieur|10 monedas iguales se convierten en 2 de nivel superior|10 moedas iguais viram 2 de nível superior|تندمج 10 عملات متساوية لتصبح عملتين من المستوى التالي|10 枚同級硬幣，自動合成 2 枚高一級硬幣',
    '点击「发牌」，获得更多硬币': 'Нажмите «Раздать», чтобы получить монеты|「딜」을 눌러 동전을 더 받으세요|「配る」をタップしてコインを増やそう|Ketuk Bagikan untuk mendapat koin|Touchez Distribuer pour obtenir des pièces|Toca Repartir para obtener monedas|Toque em Distribuir para receber moedas|اضغط على توزيع للحصول على عملات إضافية|點擊「發牌」，獲得更多硬幣',
    '合成 5 级硬币即可解锁新槽位！': 'Создайте монету 5-го уровня, чтобы открыть ячейки!|5레벨 동전을 합성해 새 슬롯을 여세요!|レベル5のコインを合成して枠を解放！|Gabungkan koin level 5 untuk membuka slot!|Fusionnez une pièce de niveau 5 pour ouvrir des cases !|¡Crea una moneda de nivel 5 para abrir casillas!|Crie uma moeda de nível 5 para abrir espaços!|ادمج عملة من المستوى 5 لفتح خانات جديدة!|合成 5 級硬幣即可解鎖新槽位！',
    '收集上方五个目标，进入下一关。': 'Достигните всех пяти целей, чтобы пройти дальше.|위의 목표 5개를 달성하면 다음 단계로 갑니다.|上の5つの目標を達成すると次のステージへ。|Capai kelima target di atas untuk lanjut.|Atteignez les cinq objectifs pour passer au niveau suivant.|Alcanza los cinco objetivos para avanzar.|Alcance as cinco metas para avançar.|حقق الأهداف الخمسة أعلاه للانتقال إلى المستوى التالي.|達成上方五個目標，進入下一關。',
    '已进入第 %d 关，继续合成更高等级硬币！': 'Уровень %d! Создавайте монеты выше уровнем!|%d단계입니다! 더 높은 레벨의 동전을 합성하세요!|ステージ %d！さらに高いレベルへ合成しよう！|Level %d! Terus gabungkan koin lebih tinggi!|Niveau %d ! Continuez les fusions !|¡Nivel %d! ¡Sigue fusionando monedas!|Nível %d! Continue juntando moedas!|وصلت إلى المستوى %d! واصل دمج العملات!|已進入第 %d 關，繼續合成更高等級硬幣！',
    '新槽位已就绪，点击发光的锁开启': 'Нажмите на светящийся замок, чтобы открыть ячейку|빛나는 자물쇠를 눌러 새 슬롯을 여세요|光る鍵をタップして新しい枠を解放|Ketuk gembok bercahaya untuk membuka slot|Touchez le cadenas lumineux pour ouvrir une case|Toca el candado brillante para abrir una casilla|Toque no cadeado brilhante para abrir um espaço|اضغط على القفل المضيء لفتح خانة جديدة|新槽位已就緒，點擊發光的鎖開啟',
    '达成上方目标即可解锁新槽位': 'Достигните следующей цели, чтобы открыть ячейки|위의 목표를 달성해 새 슬롯을 여세요|上の目標を達成して新しい枠を解放|Capai target di atas untuk membuka slot|Atteignez le prochain objectif pour ouvrir des cases|Alcanza el objetivo para abrir casillas|Alcance a meta para abrir espaços|حقق الهدف أعلاه لفتح خانات جديدة|達成上方目標即可解鎖新槽位',
    '只能移到空槽或相同的顶部硬币上': 'Перемещайте в пустую ячейку или на такую же монету|빈 슬롯이나 맨 위 동전이 같은 슬롯으로 옮기세요|空の枠か一番上が同じコインの枠に移動できます|Pindahkan ke slot kosong atau koin atas yang sama|Déplacez vers une case vide ou une pièce identique|Mueve a una casilla vacía o con la misma moneda arriba|Mova para um espaço vazio ou uma moeda igual no topo|انقل إلى خانة فارغة أو عملة مماثلة في الأعلى|只能移到空槽或相同的頂部硬幣上',
    '%d 连合！': '%d слияний!|%d 연속 합성!|%d 連続合成！|%d gabungan!|%d fusions !|¡%d fusiones!|%d fusões!|%d عمليات دمج!|%d 連合！',
    '槽位已满': 'Все ячейки заполнены|슬롯이 가득 찼습니다|枠がいっぱいです|Slot penuh|Plateau plein|Tablero lleno|Tabuleiro cheio|الخانات ممتلئة|槽位已滿',
    '整理同级硬币释放空间，或重新挑战当前关卡。': 'Сортируйте одинаковые монеты или начните уровень заново.|같은 레벨의 동전을 정리하거나 다시 도전하세요.|同じコインを整理するか、このステージをやり直そう。|Susun koin selevel atau ulangi level ini.|Triez les pièces identiques ou recommencez ce niveau.|Ordena las monedas iguales o reinicia el nivel.|Organize moedas iguais ou reinicie o nível.|رتّب العملات المتساوية لتوفير مساحة أو أعد المستوى.|整理同級硬幣釋放空間，或重新挑戰目前關卡。',
    '整理（剩余 %d 次）': 'Сортировать (осталось %d)|정리 (남은 횟수 %d)|整理（残り %d 回）|Susun (sisa %d)|Trier (%d restants)|Ordenar (%d restantes)|Organizar (%d restantes)|ترتيب (متبقي %d)|整理（剩餘 %d 次）',
    '继续合并相同等级的硬币': 'Продолжайте объединять одинаковые монеты|같은 레벨의 동전을 계속 합성하세요|同じレベルのコインを合成しよう|Terus gabungkan koin selevel|Continuez à fusionner les pièces identiques|Sigue fusionando monedas del mismo nivel|Continue juntando moedas do mesmo nível|واصل دمج العملات من المستوى نفسه|繼續合併相同等級的硬幣',
    '合成上方的最终目标硬币，进入下一关。': 'Создайте последнюю целевую монету, чтобы пройти дальше.|마지막 목표 동전을 합성해 다음 단계로 가세요.|最後の目標コインを合成して次のステージへ。|Gabungkan koin target terakhir untuk lanjut.|Fusionnez la dernière pièce cible pour avancer.|Crea la última moneda objetivo para avanzar.|Crie a última moeda da meta para avançar.|ادمج عملة الهدف الأخير للانتقال إلى المستوى التالي.|合成上方的最終目標硬幣，進入下一關。',
    '继续合成，挑战更高等级！': 'Продолжайте слияния и достигайте новых уровней!|계속 합성해서 더 높은 레벨에 도전하세요!|合成を続けてさらに高いレベルへ！|Terus gabungkan untuk level lebih tinggi!|Continuez les fusions vers de nouveaux niveaux !|¡Sigue fusionando para llegar más alto!|Continue juntando para alcançar níveis maiores!|واصل الدمج للوصول إلى مستويات أعلى!|繼續合成，挑戰更高等級！',
    'challenge.summary': 'Лучшая монета %d · Пройдено %d/100 · Золото %d|최고 동전 %d레벨 · 완료 %d/100 · 골드 %d|最高レベル %d · クリア %d/100 · ゴールド %d|Koin tertinggi %d · Selesai %d/100 · Emas %d|Pièce max. %d · Réussis %d/100 · Or %d|Moneda máx. %d · Completados %d/100 · Oro %d|Moeda máx. %d · Concluídos %d/100 · Ouro %d|أعلى عملة %d · المكتمل %d/100 · الذهب %d|最高硬幣 %d 級 · 已完成 %d/100 · 金幣 %d',
    'challenge.complete': 'Испытание пройдено!|도전 완료!|チャレンジクリア！|Tantangan selesai!|Défi réussi !|¡Desafío completado!|Desafio concluído!|اكتمل التحدي!|挑戰完成！',
    'challenge.locked': 'Закрыто|잠김|未解放|Terkunci|Verrouillé|Bloqueado|Bloqueado|مغلق|尚未解鎖',
    'challenge.unlock': 'Создайте монету уровня %d для открытия|%d레벨 동전을 합성하면 해제|レベル %d のコインで解放|Capai koin level %d untuk membuka|Pièce de niveau %d requise|Alcanza una moneda de nivel %d|Alcance uma moeda de nível %d|أنشئ عملة من المستوى %d للفتح|合成 %d 級硬幣解鎖',
    'challenge.best_short': 'Рекорд %s|최고 %s|ベスト %s|Terbaik %s|Record %s|Mejor %s|Melhor %s|الأفضل %s|最佳 %s',
    'challenge.best': 'Лучшее время: %s|최고 기록: %s|ベストタイム：%s|Waktu terbaik: %s|Meilleur temps : %s|Mejor tiempo: %s|Melhor tempo: %s|أفضل وقت: %s|最佳耗時：%s',
    'challenge.levels': 'Выбор уровня|도전 선택|ステージ選択|Pilih level|Choisir un niveau|Elegir nivel|Escolher nível|اختيار المستوى|挑戰選關',
    'challenge.result': 'Время: %s\\nРекорд: %s|기록: %s\\n최고: %s|タイム：%s\\nベスト：%s|Waktu: %s\\nTerbaik: %s|Temps : %s\\nRecord : %s|Tiempo: %s\\nMejor: %s|Tempo: %s\\nMelhor: %s|الوقت: %s\\nالأفضل: %s|本次耗時：%s\\n最佳耗時：%s',
    'challenge.first_reward': 'Первое прохождение · Золото +1|첫 완료 · 골드 +1|初クリア · ゴールド +1|Selesai pertama · Emas +1|Première réussite · Or +1|Primera victoria · Oro +1|Primeira vitória · Ouro +1|أول إكمال · ذهب +1|首次完成 · 金幣 +1',
    'challenge.new_record': 'Новый рекорд!|최고 기록 갱신!|ベスト更新！|Rekor baru!|Nouveau record !|¡Nuevo récord!|Novo recorde!|رقم قياسي جديد!|刷新最佳紀錄！',
    'challenge.tutorial': 'Обучение испытаниям|도전 튜토리얼|チャレンジの遊び方|Tutorial tantangan|Tutoriel du défi|Tutorial del desafío|Tutorial do desafio|شرح التحدي|挑戰教學',
    'challenge.hint': 'Заполните цели 10 монетами нужного цвета. Одноцветные стопки можно менять местами.|목표 색 동전 10개를 채우세요. 단색 더미끼리 교환할 수 있습니다.|目標の色で10枚そろえよう。単色の山同士は交換できます。|Isi target dengan 10 koin sewarna. Tumpukan satu warna bisa ditukar.|Remplissez les cibles avec 10 pièces assorties. Les piles unicolores peuvent être échangées.|Llena los objetivos con 10 monedas del mismo color. Las pilas de un color se pueden intercambiar.|Preencha as metas com 10 moedas da mesma cor. Pilhas de uma cor podem ser trocadas.|املأ الأهداف بعشر عملات مطابقة. يمكن تبديل الكومات ذات اللون الواحد.|按箭頭顏色放滿 10 枚 · 整疊不同顏色可交換',
    'challenge.progress': 'Цели %d / %d|목표 %d / %d|目標 %d / %d|Target %d / %d|Objectifs %d / %d|Objetivos %d / %d|Metas %d / %d|الأهداف %d / %d|目標完成 %d / %d',
    'challenge.finished_board': 'Все цели достигнуты|모든 목표 완료|すべての目標を達成|Semua target selesai|Tous les objectifs atteints|Todos los objetivos completos|Todas as metas concluídas|اكتملت جميع الأهداف|全部目標已完成',
    'challenge.slot': 'Ячейка %d · %d/10|슬롯 %d · %d/10|枠 %d · %d/10|Slot %d · %d/10|Case %d · %d/10|Casilla %d · %d/10|Espaço %d · %d/10|الخانة %d · %d/10|槽位 %d · %d/10',
    'challenge.target': 'Цвет цели %d|목표 색상 %d|目標の色 %d|Warna target %d|Couleur cible %d|Color objetivo %d|Cor da meta %d|لون الهدف %d|目標顏色 %d',
    'challenge.unlock_body': 'Создайте монету уровня %d в основной игре, чтобы открыть|일반 모드에서 %d레벨 동전을 합성하면 해제됩니다|通常モードでレベル %d のコインを合成すると解放|Gabungkan koin level %d di permainan utama untuk membuka|Fusionnez une pièce de niveau %d dans le jeu principal pour débloquer|Crea una moneda de nivel %d en el juego principal para desbloquear|Crie uma moeda de nível %d no jogo principal para desbloquear|ادمج عملة من المستوى %d في اللعبة الرئيسية للفتح|主玩法合成 %d 級硬幣解鎖',
    'challenge.swipe_hint': 'Листайте для выбора уровня|좌우로 밀어 단계 선택|左右にスワイプして選択|Geser untuk memilih level|Balayez pour choisir|Desliza para elegir nivel|Deslize para escolher|اسحب لاختيار المستوى|左右滑動選關',
    'challenge.video_share': 'Поделиться видео|영상 공유|動画を共有|Bagikan video|Partager la vidéo|Compartir vídeo|Partilhar vídeo|مشاركة الفيديو|分享影片',
}
ALIASES = {
    'challenge.next': '进入下一关', 'challenge.dismiss': '关闭',
    '新槽位已就绪，点击发光的锁开启。': '新槽位已就绪，点击发光的锁开启',
}


def flatten(data, prefix=''):
    result = {}
    for key, value in data.items():
        name = f'{prefix}.{key}' if prefix else key
        if isinstance(value, dict):
            result.update(flatten(value, name))
        else:
            result[name] = value
    return result


def main():
    target = ROOT / 'translations/menu.csv'
    with target.open(encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    references = {}
    for path in (ROOT / 'docs/rea-reference/raw-configs').glob('*.json'):
        data = json.loads(path.read_text(encoding='utf-8'))
        try:
            name, body = data[5][0][1:3]
        except (IndexError, KeyError, TypeError, ValueError):
            continue
        if isinstance(body, dict) and 'setting' in body:
            references[name.replace('-', '_')] = flatten(body)
    for row in rows:
        row['zh_CN'] = row.get('zh_CN', row.get('zh'))
        row['en_US'] = row.get('en_US', row.get('en'))
    for row in rows:
        key = row['keys']
        lookup = ALIASES.get(key, key)
        reference = REFERENCE_KEYS.get(lookup)
        if lookup.startswith('normal.'):
            reference = lookup.replace('normal.guide.', 'guide.').replace('normal.', 'game.')
        if lookup.startswith('time.'):
            reference = lookup
        if lookup in CUSTOM:
            values = CUSTOM[lookup].split('|')
            assert len(values) == len(EXTRA_LOCALES), lookup
            row.update(zip(EXTRA_LOCALES, values))
        elif reference:
            for locale in EXTRA_LOCALES:
                row[locale] = references[locale][reference].replace('{0}', '%d')
        else:
            raise ValueError(f'No translation for {key}')
        expected = re.findall(r'%(?:\d+\$)?[dsf]', row['en_US'])
        for locale in LOCALES:
            assert row[locale] and '\ufffd' not in row[locale], (key, locale)
            assert re.findall(r'%(?:\d+\$)?[dsf]', row[locale]) == expected, (key, locale)
            row[locale] = row[locale].replace('\n', '\\n')
    with target.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, ['keys', *LOCALES], extrasaction='ignore', lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    print(f'{len(rows)} keys x {len(LOCALES)} languages; placeholders verified')


if __name__ == '__main__':
    main()

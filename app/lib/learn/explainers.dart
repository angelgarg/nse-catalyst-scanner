import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// Bite-sized "Why?" explainers (education review 2026-10-29). Concept-level only:
/// no named stocks, no live prices, nothing forward-looking, so they are safe next
/// to any spike card. Hindi uses neutral words ("asaamaanya chaal", never "tezi").
/// Hindi copy should get a native-speaker review before a big Hindi push.
class Explainer {
  final String title, en, titleHi, hi;
  const Explainer(this.title, this.en, this.titleHi, this.hi);
}

const explainers = <String, Explainer>{
  'vs_market': Explainer(
    'Market move vs own move',
    'If NIFTY falls 2% and a stock that usually moves 1:1 with NIFTY also falls 2%, nothing special happened: '
        'it just went with the market. Spikewise takes out the market\'s part of the move and looks at what is left.\n\n'
        '"Did better than NIFTY explains" means the left-over part was positive, even if the price itself fell. '
        '"Did worse" means it was negative, even if the price rose.',
    'Market ki chaal vs stock ki apni chaal',
    'Agar NIFTY 2% gira aur jo stock aam taur par NIFTY ke saath 1:1 chalta hai woh bhi 2% gira, toh kuch khaas nahi hua — '
        'woh bas market ke saath chala. Spikewise market ka hissa hata kar dekhta hai ki kya bacha.\n\n'
        '"NIFTY se behtar" ka matlab hai bacha hua hissa positive tha, chahe daam gira ho. '
        '"NIFTY se kamzor" ka matlab negative tha, chahe daam badha ho.',
  ),
  'move_size': Explainer(
    'Big, very big, rare',
    'We compare the stock\'s own move with its normal size over the previous 20 trading days.\n\n'
        '• Big move: 1.5–2× its normal size\n• Very big move: 2–3×\n• Rare move: more than 3×\n\n'
        'A big move tells you something unusual happened. It does not tell you what happens next.',
    'Badi, bahut badi, asaamaanya chaal',
    'Hum stock ki apni chaal ko pichhle 20 trading dino ki uski normal chaal se milate hain.\n\n'
        '• Badi chaal: normal ka 1.5–2 guna\n• Bahut badi: 2–3 guna\n• Asaamaanya: 3 guna se zyada\n\n'
        'Badi chaal batati hai ki kuch alag hua. Yeh nahi batati ki aage kya hoga.',
  ),
  'volume': Explainer(
    'What "× usual volume" means',
    'Volume is how many shares changed hands. "2.4× usual volume" means 2.4 times the average of the previous '
        '20 trading days.\n\nHeavy volume says many people traded. It does not say which way, or why: every trade '
        'has a buyer and a seller.',
    '"× usual volume" ka matlab',
    'Volume yaani kitne shares ka len-den hua. "2.4× usual volume" ka matlab pichhle 20 trading dino ke average ka 2.4 guna.\n\n'
        'Zyada volume batata hai ki bahut logon ne trade kiya. Isse direction ya wajah nahi pata chalti — '
        'har saude mein ek khareedne wala aur ek bechne wala hota hai.',
  ),
  'spike_rule': Explainer(
    'What makes a spike',
    'Two doors, and both must open:\n\n1. The stock\'s own move (after taking out NIFTY\'s part) is more than '
        '1.5× its normal size.\n2. Volume is at least 1.25× its 20-day average.\n\n'
        'Both are measured against the 20 sessions before the day, so a big day can\'t water down its own baseline.',
    'Spike kab banta hai',
    'Do darwaaze, dono khulne chahiye:\n\n1. Stock ki apni chaal (NIFTY ka hissa hatane ke baad) uski normal chaal se '
        '1.5 guna se zyada ho.\n2. Volume pichhle 20 din ke average ka kam se kam 1.25 guna ho.\n\n'
        'Dono us din se pehle ke 20 sessions se naape jaate hain.',
  ),
  'filing': Explainer(
    'What is a company filing?',
    'Listed companies must tell NSE/BSE about important events: results, orders, deals, management changes, '
        'dividends. These official filings are free to read and public to everyone at the same time.\n\n'
        'Spikewise shows the filing closest to a spike. It may or may not be the reason, so read it and decide '
        'for yourself.',
    'Company filing kya hoti hai?',
    'Listed companies ko zaroori baatein NSE/BSE ko batani padti hain — results, orders, deals, management badlav, '
        'dividend. Yeh official filing free mein padh sakte hain aur sabke liye ek saath public hoti hai.\n\n'
        'Spikewise spike ke sabse paas wali filing dikhata hai. Woh wajah ho bhi sakti hai, nahi bhi — padhiye aur khud tay kijiye.',
  ),
  'filing_check': Explainer(
    'Is this filing the reason?',
    'Five quick checks:\n1. Was it filed before the move, or after?\n2. Is it specific (results, order, deal) or '
        'routine paperwork?\n3. Is the same filing next to more than one spike?\n4. Did many stocks move that day?\n'
        '5. Does it contain a number or a decision?\n\nIf most answers are "no", the filing is probably just nearby, not the reason.',
    'Kya yeh filing hi wajah hai?',
    'Paanch sawaal:\n1. Filing chaal se pehle aayi ya baad mein?\n2. Kya yeh specific hai (results, order, deal) ya '
        'routine kaagzi kaarwai?\n3. Kya yahi filing ek se zyada spike ke paas hai?\n4. Kya us din bahut saare stocks hile?\n'
        '5. Kya isme koi number ya faisla hai?\n\nAgar zyada jawab "nahi" hain, toh filing shayad bas paas mein hai, wajah nahi.',
  ),
  'routine_filing': Explainer(
    'Routine filings',
    'Some filings are regular paperwork: general updates, meeting notices, appointments. They are shown only when '
        'nothing more specific was filed near that day, and are marked "routine" because they rarely explain a big move.\n\n'
        'Pure compliance documents (trading-window closures, depository certificates, newspaper copies) are never shown as reasons.',
    'Routine filings',
    'Kuch filings sirf regular kaagzi kaarwai hoti hain: general updates, meeting notice, appointments. Yeh tabhi dikhti hain '
        'jab us din ke paas koi aur specific filing na ho, aur "routine" likhi hoti hain kyunki yeh badi chaal ki wajah kam hi hoti hain.',
  ),
  'no_filing': Explainer(
    'Moved with no filing',
    'Prices can move on sector news, a rival\'s results, big-investor trades, index changes, or rumours. '
        '"No filing found" means we found none near that date, not that there was no reason.\n\n'
        'Filings are only checked for spikes in the last 30 days.',
    'Bina filing ke chaal',
    'Daam sector ki khabar, kisi rival ke results, bade investors ke saude, index badlav ya afwaah se bhi hil sakte hain. '
        '"Filing nahi mili" ka matlab hai hume us din ke paas koi nahi mili — yeh nahi ki koi wajah nahi thi.\n\n'
        'Filings sirf pichhle 30 din ke spikes ke liye check hoti hain.',
  ),
  'beta': Explainer(
    'Moves with NIFTY',
    '"Moves with NIFTY 1.2×" means that over the last 20 trading days the stock tended to move about 1.2% for every '
        '1% NIFTY move. It is how Spikewise estimates the market\'s part of a move. It changes over time.',
    'NIFTY ke saath chaal',
    '"NIFTY ke saath 1.2×" ka matlab pichhle 20 trading dino mein NIFTY ke har 1% par stock lagbhag 1.2% hila. '
        'Isi se Spikewise chaal mein market ka hissa nikalta hai. Yeh samay ke saath badalta hai.',
  ),
  'limits': Explainer(
    'What Spikewise can\'t tell you',
    'We can\'t tell you why a stock moved, what it will do next, or whether to buy or sell. We show you where to '
        'look: the size of the move, the trading activity, and the official filing nearby. The decision is always yours.',
    'Spikewise kya nahi bata sakta',
    'Hum nahi bata sakte ki stock kyun hila, aage kya karega, ya khareedna-bechna chahiye ya nahi. Hum dikhate hain '
        'kahan dekhna hai: chaal kitni badi thi, trading kitni hui, aur paas ki official filing. Faisla hamesha aapka.',
  ),
};

const kHindiKey = 'learn_hindi';

void showExplainer(BuildContext context, String key) {
  final e = explainers[key];
  if (e == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ExplainerSheet(e: e),
  );
}

class _ExplainerSheet extends ConsumerWidget {
  final Explainer e;
  const _ExplainerSheet({required this.e});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hi = ref.watch(boolPrefProvider(kHindiKey));
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child:
                        Text(hi ? e.titleHi : e.title, style: tt.titleLarge)),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('EN')),
                    ButtonSegment(value: true, label: Text('हिं'))
                  ],
                  selected: {hi},
                  onSelectionChanged: (v) => ref
                      .read(boolPrefProvider(kHindiKey).notifier)
                      .set(v.first),
                ),
              ]),
              const SizedBox(height: 12),
              Flexible(
                  child: SingleChildScrollView(
                      child: Text(hi ? e.hi : e.en, style: tt.bodyLarge))),
              const SizedBox(height: 12),
              Text('Educational, not investment advice.', style: tt.bodySmall),
            ]),
      ),
    );
  }
}

/// Small tappable "why" chip that opens an explainer.
class WhyChip extends StatelessWidget {
  final String label;
  final String explainer;
  final IconData? icon;
  const WhyChip(
      {super.key, required this.label, required this.explainer, this.icon});

  @override
  Widget build(BuildContext context) => ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon ?? Icons.help_outline, size: 16),
        label: Text(label),
        tooltip: 'What does this mean?',
        onPressed: () => showExplainer(context, explainer),
      );
}

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hi = ref.watch(boolPrefProvider(kHindiKey));
    return Scaffold(
      appBar:
          AppBar(title: Text(hi ? 'Samjhiye' : 'Learn the basics'), actions: [
        TextButton(
          onPressed: () =>
              ref.read(boolPrefProvider(kHindiKey).notifier).set(!hi),
          child: Text(hi ? 'English' : 'हिन्दी'),
        ),
      ]),
      body: ListView(children: [
        for (final entry in explainers.entries)
          ListTile(
            title: Text(hi ? entry.value.titleHi : entry.value.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showExplainer(context, entry.key),
          ),
      ]),
    );
  }
}

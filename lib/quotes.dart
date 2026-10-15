import 'dart:math';

/// Original lines plus paraphrased ideas (not verbatim quotes), each credited
/// to the book it comes from.
class Quote {
  final String text;
  final String source;
  const Quote(this.text, [this.source = '']);
}

const builtInQuotes = <Quote>[
  Quote('Keep going.'),
  Quote('Consistency beats intensity.'),
  Quote('Small steps, every single day.'),
  Quote('Show up today. That is the whole trick.'),
  Quote('One block at a time.'),
  Quote('Done daily beats done perfectly.'),
  Quote('Little by little becomes a lot.'),
  Quote('Your systems will carry you further than your goals.', 'Idea from Atomic Habits'),
  Quote('Every block you show up for is proof of who you are becoming.', 'Idea from Atomic Habits'),
  Quote('Tiny gains, repeated daily, compound into big change.', 'Idea from Atomic Habits'),
  Quote('Missed one? Fine. Just don’t let it turn into two.', 'Idea from Atomic Habits'),
  Quote('Make the next step so small it is easy to begin.', 'Idea from Atomic Habits'),
  Quote('Find the one task that makes the rest easier. Start there.', 'Idea from The ONE Thing'),
  Quote('Guard this block like your most important meeting.', 'Idea from The ONE Thing'),
  Quote('Go small: fewer things, full attention.', 'Idea from The ONE Thing'),
  Quote('Big results are built in sequence, one domino at a time.', 'Idea from The ONE Thing'),
];

const skipQuote = Quote('Missed one? Fine. Just don’t let it turn into two.', 'Idea from Atomic Habits');

final _rng = Random();

Quote randomQuote(List<String> custom) {
  final all = [...builtInQuotes, ...custom.map((t) => Quote(t))];
  return all[_rng.nextInt(all.length)];
}

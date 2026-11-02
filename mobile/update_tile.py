path = 'mobile/lib/ui/widgets/search/search_song_tile.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

old_block = '''              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),'''

new_block = '''              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
      if (song.matchedLyricSnippet != null && song.matchedLyricSnippet!.isNotEmpty) ...[
        const SizedBox(height: 3),
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 10, color: AppColors.electricCyan),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '"${song.matchedLyricSnippet}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.electricCyan,
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  ),'''

# Try both CRLF and LF
if old_block.replace('\n', '\r\n') in text:
    text = text.replace(old_block.replace('\n', '\r\n'), new_block.replace('\n', '\r\n'))
    print("Replaced CRLF")
elif old_block in text:
    text = text.replace(old_block, new_block)
    print("Replaced LF")
else:
    print("Not found")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

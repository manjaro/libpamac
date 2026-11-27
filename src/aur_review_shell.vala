/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Pamac {
	// A deliberately limited lexical view for advisory heuristics. It preserves
	// newlines, masks literal arguments/comments, and exposes substitutions.
	// It does not resolve variables, aliases, eval strings or Bash grammar.
	internal class AurReviewShell : Object {
		public bool limited { get; private set; }

		public string mask_data (string script, bool arguments = false) {
			var prepared = new StringBuilder ();
			string? delimiter = null;
			bool quoted = false;
			bool strip_tabs = false;
			var heredoc = /<<(-?)[ \t]*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2/;
			foreach (unowned string line in script.split ("\n")) {
				if (delimiter != null) {
					string candidate = strip_tabs ? line.replace ("\t", "") : line;
					if (candidate == delimiter) {
						delimiter = null;
					} else if (!quoted) {
						// An unquoted heredoc expands command substitutions, just
						// like a double-quoted argument. Keep those executable.
						int index = 0;
						prepared.append (region (line, ref index, '\0', '"', arguments, 0, true));
					}
					prepared.append_c ('\n');
					continue;
				}
				int index = 0;
				// Quoting is processed over the whole script below, so multiline
				// strings stay data. This pass only handles heredoc bodies.
				prepared.append (line);
				prepared.append_c ('\n');
				MatchInfo match;
				if (heredoc.match (line, 0, out match) && !line.strip ().has_prefix ("#")) {
					// Ignore here-strings (<<<) and quoted examples of <<.
					int start;
					int end;
					match.fetch_pos (0, out start, out end);
					string line_code = region (line, ref index, '\0', '\0', false);
					if ((start == 0 || line[start - 1] != '<') && start + 2 <= line_code.length && line_code.substring (start, 2) == "<<") {
						delimiter = match.fetch (3);
						quoted = match.fetch (2) != "";
						strip_tabs = match.fetch (1) == "-";
					}
				}
			}
			int index = 0;
			return region (prepared.str, ref index, '\0', '\0', arguments);
		}

		// Match executable write operations against their destination operands.
		// Both views must have matching offsets; the argument view retains paths
		// in quotes while the code view masks quoted examples and comments.
		public static bool writes_shell_startup (string code, string arguments) {
			var redirects = /(?<![<>])>{1,2}\|?(?![>&|])/;
			MatchInfo match;
			redirects.match (code, 0, out match);
			while (match.matches ()) {
				int start;
				int end;
				match.fetch_pos (0, out start, out end);
				if (startup_path (argument_at (arguments, end))) {
					return true;
				}
				try {
					match.next ();
				} catch (RegexError e) {
					break;
				}
			}
			var writers = /(?:^|[;|&({]|\bthen\b|\bdo\b)\s*(?:(?:\/usr\/bin\/|\/bin\/)?(?:sudo|doas|pkexec|run0|command|builtin|env)\s+)*(?:\/usr\/bin\/|\/bin\/)?(tee|cp|install|sed)\b/;
			writers.match (code, 0, out match);
			while (match.matches ()) {
				int start;
				int end;
				match.fetch_pos (0, out start, out end);
				int stop = end;
				while (stop < code.length && ";|&)>\n".index_of_char (code[stop]) < 0) {
					stop++;
				}
				string writer = match.fetch (1);
				string operands = arguments.substring (end, int.min (stop, arguments.length) - end);
				string[] words = /[ \t\r]+/.split (operands.strip ());
				if (writer == "tee") {
					foreach (unowned string word in words) {
						if (startup_path (word)) {
							return true;
						}
					}
				} else if (writer == "sed") {
					// Plain sed reads files; only its in-place form writes them.
					if (/(?:^|\s)(?:--in-place(?:=\S*)?|-[a-zA-Z]*i\S*)(?:\s|$)/.match (operands) &&
						words.length > 0 && startup_path (words[words.length - 1])) {
						return true;
					}
				} else {
					// cp/install normally write the final operand. With -t, the
					// destination is a directory instead; inspect that explicitly.
					if (words.length > 0 && startup_path (words[words.length - 1])) {
						return true;
					}
					for (int i = 0; i < words.length; i++) {
						if ((words[i] == "-t" || words[i] == "--target-directory") && i + 1 < words.length &&
							startup_path (words[i + 1], true)) {
							return true;
						}
						if (words[i].has_prefix ("--target-directory=") && startup_path (words[i].substring (19), true)) {
							return true;
						}
					}
				}
				try {
					match.next ();
				} catch (RegexError e) {
					break;
				}
			}
			return false;
		}

		static string argument_at (string arguments, int offset) {
			int start = offset;
			while (start < arguments.length && arguments[start].isspace ()) {
				start++;
			}
			int end = start;
			while (end < arguments.length && !arguments[end].isspace () &&
				";|&)<>".index_of_char (arguments[end]) < 0) {
				end++;
			}
			return arguments.substring (start, end - start);
		}

		static bool startup_path (string path, bool directory = false) {
			string candidate = path;
			if (directory) {
				candidate = path.has_suffix ("/") ? path + "startup.sh" : path + "/startup.sh";
			}
			// Anchoring keeps normal packaging into $pkgdir, $srcdir or a
			// relative staging directory separate from writes to live files.
			var system_path = /^\/etc\/(?:profile|bash\.bashrc|bashrc|bash\/bashrc|(?:zsh\/)?(?:zshenv|zprofile|zshrc|zlogin|zlogout)|profile\.d\/[^\/]+|fish\/(?:config\.fish|conf\.d\/[^\/]+))$/;
			var home_path = /^(?:~|\$(?:HOME|\{HOME\})|\/home\/[^\/]+|\/root)\/(?:\.(?:profile|bashrc|bash_profile|bash_login|bash_logout|zshenv|zprofile|zshrc|zlogin|zlogout)|\.config\/fish\/(?:config\.fish|conf\.d\/[^\/]+))$/;
			var config_path = /^\$(?:XDG_CONFIG_HOME|\{XDG_CONFIG_HOME\})\/fish\/(?:config\.fish|conf\.d\/[^\/]+)$/;
			var zsh_path = /^\$(?:ZDOTDIR|\{ZDOTDIR\})\/\.(?:zshenv|zprofile|zshrc|zlogin|zlogout)$/;
			return system_path.match (candidate) || home_path.match (candidate) || config_path.match (candidate) || zsh_path.match (candidate);
		}

		string region (string text, ref int index, char terminator, char initial_quote, bool arguments, int depth = 0, bool heredoc_body = false) {
			if (depth >= 32) {
				limited = true;
				string remaining = text.substring (index);
				index = text.length;
				return remaining;
			}
			var result = new StringBuilder ();
			char quote = initial_quote;
			int parentheses = 0;
			while (index < text.length) {
				char c = text[index];
				if (quote == '\0' && c == terminator && parentheses == 0) {
					index++;
					return result.str;
				}
				if (c == '\\' && quote != '\'') {
					result.append_c (quote == '\0' || arguments ? c : ' ');
					index++;
					if (index < text.length) {
						c = text[index++];
						result.append_c (c == '\n' || quote == '\0' || arguments ? c : ' ');
					}
					continue;
				}
				if (quote != '\'' && c == '$' && index + 1 < text.length && text[index + 1] == '(') {
					index += 2;
					result.append ("$(");
					result.append (region (text, ref index, ')', '\0', arguments, depth + 1));
					result.append_c (')');
					continue;
				}
				if (quote != '\'' && c == '`') {
					index++;
					result.append_c ('`');
					result.append (region (text, ref index, '`', '\0', arguments, depth + 1));
					result.append_c ('`');
					continue;
				}
				if (quote == '\0' && c == '#' && (index == 0 || text[index - 1].isspace () || text[index - 1] == ';')) {
					while (index < text.length && text[index] != '\n') {
						result.append_c (' ');
						index++;
					}
					continue;
				}
				if (quote == '\0' && (c == '\'' || c == '"')) {
					quote = c;
					result.append_c (' ');
				} else if (quote != '\0' && c == quote && !heredoc_body) {
					quote = '\0';
					result.append_c (' ');
				} else {
					if (quote == '\0') {
						if (c == '(') {
							parentheses++;
						} else if (c == ')' && parentheses > 0) {
							parentheses--;
						}
					}
					result.append_c (quote == '\0' || arguments || c == '\n' ? c : ' ');
				}
				index++;
			}
			return result.str;
		}
	}
}

/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Pamac {
	public enum AurReviewSeverity {
		NOTE,
		WARNING
	}

	public enum AurReviewFileStatus {
		PENDING,
		SCANNED,
		PARTIAL,
		SKIPPED
	}

	public class AurReviewFinding : Object {
		public string id { get; construct; }
		public AurReviewSeverity severity { get; construct; }
		public string message { get; construct; }
		public string? filename { get; construct; }
		public int line { get; construct; }

		internal AurReviewFinding (string id, AurReviewSeverity severity, string message, string? filename = null, int line = 0) {
			Object (id: id, severity: severity, message: message, filename: filename, line: line);
		}
	}

	public class AurReviewFile : Object {
		public string filename { get; construct; }
		public AurReviewFileStatus status { get; internal set; }
		public string? reason { get; internal set; }

		internal AurReviewFile (string filename) {
			Object (filename: filename);
		}
	}

	// Advisory findings for frontends. An empty report is not a safety verdict.
	public class AurReview : Object {
		public GenericArray<AurReviewFinding> findings { get; private set; }
		public GenericArray<AurReviewFile> files { get; private set; }
		// Coverage of supplied .SRCINFO and declared local inputs, not a safety verdict.
		// Downloaded sources, generated code and undeclared inputs are outside this scope.
		public bool coverage_complete {
			get {
				foreach (var file in files) {
					if (file.status != AurReviewFileStatus.SCANNED) {
						return false;
					}
				}
				return true;
			}
		}

		public GenericArray<string> notes { get; private set; }
		public GenericArray<string> warnings { get; private set; }
		public GenericArray<string> source_hosts { get; private set; }

		// Pass existing .SRCINFO text. Do not run makepkg to obtain it from
		// an unreviewed PKGBUILD. No scripts are executed or URLs contacted here.
		public AurReview (string? srcinfo, uint64 votes, double popularity) {
			findings = new GenericArray<AurReviewFinding> ();
			files = new GenericArray<AurReviewFile> ();
			expect_file ("PKGBUILD");
			var metadata = expect_file (".SRCINFO");
			notes = new GenericArray<string> ();
			warnings = new GenericArray<string> ();
			source_hosts = new GenericArray<string> ();
			if (votes < 3 && popularity < 0.05) {
				add_finding ("metadata.few-votes", AurReviewSeverity.NOTE, dgettext (null, "This AUR package has few votes (votes: %s). Problems in rarely used packages may go unnoticed for longer.").printf (votes.to_string ()));
			}
			if (srcinfo == null || srcinfo.strip () == "") {
				add_finding ("scan.no-srcinfo", AurReviewSeverity.NOTE, dgettext (null, "No .SRCINFO text was supplied for review."));
				return;
			}
			metadata.status = AurReviewFileStatus.SCANNED;
			var seen_hosts = new HashTable<string, bool> (str_hash, str_equal);
			var sources = new HashTable<string, int> (str_hash, str_equal);
			var checksums = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			bool skips_checksum = false;
			bool insecure_transport = false;
			bool plain_http = false;
			bool ip_host = false;
			bool floating_git = false;
			bool has_install_script = false;
			bool has_package = false;
			foreach (unowned string line in srcinfo.split ("\n")) {
				string[] entry = line.split ("=", 2);
				if (entry.length != 2) {
					continue;
				}
				string key = entry[0].strip ();
				string full_key = key;
				int suffix = key.index_of_char ('_');
				if (suffix >= 0) {
					key = key.substring (0, suffix);
				}
				string value = entry[1].strip ();
				if (value == "") {
					continue;
				}
				switch (key) {
					case "pkgbase": case "pkgname":
						has_package = true;
						break;
					case "source":
						sources.insert (full_key, sources.lookup (full_key) + 1);
						if (!("://" in value)) {
							expect_file (value);
						}
						var uri = source_uri (value);
						if (uri == null) {
							break;
						}
						unowned string? host = uri.get_host ();
						unowned string scheme = uri.get_scheme ();
						if (scheme.has_prefix ("git+") || scheme == "git") {
							unowned string? fragment = uri.get_fragment ();
							floating_git = floating_git || fragment == null || !/^commit=(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$/.match (fragment);
						}
						if (host == null || host == "" || scheme == "file") {
							break;
						}
						plain_http = plain_http || scheme == "http" || scheme.has_suffix ("+http");
						string normalized = host.ascii_down ();
						ip_host = ip_host || Hostname.is_ip_address (normalized);
						insecure_transport = insecure_transport || /(?:^|\+)(?:ftp|git)$/.match (scheme);
						if (!seen_hosts.contains (normalized)) {
							seen_hosts.insert (normalized, true);
							source_hosts.add ((owned) normalized);
						}
						break;
					case "install":
						has_install_script = true;
						expect_file (value);
						break;
					case "md5sums": case "sha1sums": case "cksums": case "cksum":
					case "sha224sums": case "sha256sums": case "sha384sums":
					case "sha512sums": case "b2sums":
						var values = checksums.lookup (full_key);
						if (values == null) {
							values = new GenericArray<string> ();
							checksums.insert (full_key, values);
						}
						values.add (value);
						skips_checksum = skips_checksum || value == "SKIP";
						break;
				}
			}
			if (!has_package) {
				metadata.status = AurReviewFileStatus.PARTIAL;
				metadata.reason = dgettext (null, "No package declaration was found in .SRCINFO.");
				add_finding ("scan.invalid-srcinfo", AurReviewSeverity.NOTE, metadata.reason, ".SRCINFO");
			}
			if (plain_http) {
				add_finding ("source.http", AurReviewSeverity.WARNING, dgettext (null, "At least one source URL uses unencrypted HTTP."));
			}
			if (insecure_transport) {
				add_finding ("source.insecure-transport", AurReviewSeverity.WARNING, dgettext (null, "At least one source uses an unencrypted FTP or Git transport."));
			}
			if (ip_host) {
				add_finding ("source.ip-host", AurReviewSeverity.NOTE, dgettext (null, "At least one source URL uses a literal IP address instead of a domain name."));
			}
			if (floating_git) {
				add_finding ("source.floating-git", AurReviewSeverity.NOTE, dgettext (null, "At least one Git source is not pinned to a full commit hash."));
			}
			check_source_checksums (sources, checksums);
			if (skips_checksum) {
				add_finding ("checksum.skip", AurReviewSeverity.NOTE, dgettext (null, "At least one source checksum is marked SKIP. Check how the source is verified."));
			}
			if (has_install_script) {
				add_finding ("script.install", AurReviewSeverity.NOTE, dgettext (null, "This package declares an install script. Review it before installing."));
			}
		}

		void check_source_checksums (HashTable<string, int> sources, HashTable<string, GenericArray<string>> checksums) {
			bool missing = false;
			bool has_weak = false;
			bool count_mismatch = false;
			bool malformed = false;
			string[] algorithms = {"sha224sums", "sha256sums", "sha384sums", "sha512sums", "b2sums",
				"md5sums", "sha1sums", "cksums", "cksum"};
			int[] hex_lengths = {56, 64, 96, 128, 128, 32, 40, 0, 0};
			checksums.foreach ((key, values) => {
				int suffix = key.index_of_char ('_');
				string source_key = suffix < 0 ? "source" : "source" + key.substring (suffix);
				count_mismatch = count_mismatch || values.length != sources.lookup (source_key);
			});
			sources.foreach ((key, count) => {
				string suffix = key.substring ("source".length);
				for (int i = 0; i < count; i++) {
					bool declared = false;
					bool strong = false;
					bool weak_only = false;
					for (int j = 0; j < algorithms.length; j++) {
						var values = checksums.lookup (algorithms[j] + suffix);
						if (values == null || i >= values.length) {
							continue;
						}
						declared = true;
						unowned string digest = values[i];
						if (digest == "SKIP") {
							continue;
						}
						var decimal = /^[0-9]+$/;
						bool valid = hex_lengths[j] == 0 ? decimal.match (digest)
							: digest.length == hex_lengths[j] && /^[0-9a-fA-F]+$/.match (digest);
						malformed = malformed || !valid;
						strong = strong || (valid && j < 5);
						weak_only = weak_only || (valid && j >= 5);
					}
					missing = missing || !declared;
					has_weak = has_weak || (weak_only && !strong);
				}
			});
			if (missing) {
				add_finding ("checksum.missing", AurReviewSeverity.WARNING, dgettext (null, "At least one source has no corresponding checksum entry in .SRCINFO."));
			}
			if (has_weak) {
				add_finding ("checksum.weak", AurReviewSeverity.WARNING, dgettext (null, "At least one source has only weak checksums."));
			}
			if (malformed) {
				add_finding ("checksum.malformed", AurReviewSeverity.WARNING, dgettext (null, "At least one source checksum has an invalid format."));
			}
			if (count_mismatch) {
				add_finding ("checksum.count-mismatch", AurReviewSeverity.WARNING, dgettext (null, "At least one checksum list does not match the number of sources in its architecture group."));
			}
		}

		// Use an AUR package obtained from Database, not a synthetic build entry.
		public static AurReview for_package (AURPackage pkg, string? srcinfo) {
			var review = new AurReview (srcinfo, pkg.numvotes, pkg.popularity);
			if (pkg.maintainer == null || pkg.maintainer == "") {
				review.add_finding ("metadata.no-maintainer", AurReviewSeverity.NOTE, dgettext (null, "This AUR package has no maintainer."));
			}
			if (pkg.outofdate != null) {
				review.add_finding ("metadata.out-of-date", AurReviewSeverity.NOTE, dgettext (null, "This AUR package is flagged out of date."));
			}
			return review;
		}

		// Scan existing PKGBUILD, .install or other shell text. These heuristics
		// use a limited lexical view, not a Bash parser or a safety verdict.
		public void scan_script (string filename, string script) {
			var network_pipe = /\b(?:curl|wget)\b[^|;&]*\|(?!\|)(?:[^|;&]*\|(?!\|))*[ \t]*(?:bash|sh|zsh|python[23]?|perl)\b/;
			var dynamic_eval = /\beval\b[^;]*(?:\$\(|`)/;
			var decoded_pipe = /\b(?:base64|xxd)\b[^|;&]*\|(?!\|)[ \t]*(?:bash|sh|zsh|python[23]?|perl)\b/;
			var sensitive_path = /(?:^|[\/\s"'])(?:\.ssh|\.gnupg|\.aws)(?:[\/\s"']|$)|\/etc\/shadow\b/;
			var tls_bypass = /\bcurl\b[^|;]*\s(?:--insecure|-[a-zA-Z]*k[a-zA-Z]*)(?:\s|$)|\bwget\b[^|;]*\s--no-check-certificate\b|\bGIT_SSL_NO_VERIFY\s*=\s*(?:true|1)\b/;
			var privilege = /(?:^|[;|&({]|\bthen\b|\bdo\b)\s*(?:(?:command|exec|env)\s+)*(?:\/usr\/bin\/|\/bin\/)?(?:sudo|doas|pkexec|run0|setcap)\s|(?:^|[;|&({]|\bthen\b|\bdo\b)\s*chmod\s+(?:[ugoa]*\+s\b|[2467][0-7]{3}\b)/;
			var system_state = /(?:^|[;|&({]|\bthen\b|\bdo\b)\s*(?:systemctl\s+(?:enable|start|restart|disable|stop)\b|(?:modprobe|insmod|useradd|usermod|groupadd|mount|pacman)\s)/;
			expect_file (filename).status = AurReviewFileStatus.SCANNED;
			var substitution_exec = /\b(?:bash|sh|zsh|python[23]?|perl)\s+<\(\s*(?:curl|wget)\b/;
			var shell = new AurReviewShell ();
			string code = shell.mask_data (script);
			string[] argument_lines = shell.mask_data (script, true).split ("\n");
			if (shell.limited) {
				var file = expect_file (filename);
				file.status = AurReviewFileStatus.PARTIAL;
				file.reason = dgettext (null, "Shell nesting limit reached; script review is partial.");
				add_finding ("scan.partial-script", AurReviewSeverity.NOTE, file.reason, filename);
			}
			int number = 0;
			int start_line = 1;
			var command = new StringBuilder ();
			var arguments = new StringBuilder ();
			foreach (unowned string physical_line in code.split ("\n")) {
				number++;
				if (number <= argument_lines.length) {
					string argument_line = argument_lines[number - 1];
					arguments.append (argument_line.has_suffix ("\\") ? argument_line.substring (0, argument_line.length - 1) : argument_line);
					arguments.append_c (' ');
				}
				string part = physical_line.strip ();
				if (command.len == 0) {
					start_line = number;
				}
				bool continued = part.has_suffix ("\\") || (part.has_suffix ("|") && !part.has_suffix ("||"));
				command.append (physical_line.has_suffix ("\\") ? physical_line.substring (0, physical_line.length - 1) : physical_line);
				command.append_c (' ');
				if (continued) {
					continue;
				}
				string line = command.str;

				if (network_pipe.match (line) || substitution_exec.match (line)) {
					script_warning ("script.download-exec", filename, start_line, dgettext (null, "Possible download piped to an interpreter."));
				}
				if (dynamic_eval.match (line)) {
					script_warning ("script.dynamic-eval", filename, start_line, dgettext (null, "Possible eval of command substitution."));
				}
				if (decoded_pipe.match (line)) {
					script_warning ("script.decode-exec", filename, start_line, dgettext (null, "Possible decoded data piped to an interpreter."));
				}
				if (sensitive_path.match (arguments.str)) {
					script_warning ("script.credentials", filename, start_line, dgettext (null, "Reference to a path that may hold credentials."));
				}
				if (tls_bypass.match (line)) {
					script_warning ("script.tls-bypass", filename, start_line, dgettext (null, "Possible bypass of TLS certificate verification."));
				}
				if (privilege.match (line)) {
					script_warning ("script.privilege", filename, start_line, dgettext (null, "Possible attempt to run with or assign elevated privileges."));
				}
				if (system_state.match (line)) {
					script_warning ("script.system-state", filename, start_line, dgettext (null, "Possible command that changes system state."));
				}
				if (AurReviewShell.writes_shell_startup (line, arguments.str)) {
					script_warning ("script.shell-startup-write", filename, start_line, dgettext (null, "Possible write to a shell startup file. Code placed there may run whenever a shell starts."));
				}
				command.truncate (0);
				arguments.truncate (0);
			}
		}

		void script_warning (string id, string filename, int line, string message) {
			add_finding (id, AurReviewSeverity.WARNING, message, filename, line);
		}

		void add_finding (string id, AurReviewSeverity severity, string message, string? filename = null, int line = 0) {
			findings.add (new AurReviewFinding (id, severity, message, filename, line));
			string text = filename == null ? message : "%s:%d: %s".printf (filename, line, message);
			if (severity == AurReviewSeverity.WARNING) {
				warnings.add (text);
			} else {
				notes.add (text);
			}
		}

		AurReviewFile expect_file (string filename) {
			foreach (var file in files) {
				if (file.filename == filename) {
					return file;
				}
			}
			var file = new AurReviewFile (filename);
			files.add (file);
			return file;
		}

		void skip_file (AurReviewFile file, string reason) {
			file.status = AurReviewFileStatus.SKIPPED;
			file.reason = reason;
			add_finding ("scan.skipped-file", AurReviewSeverity.NOTE, reason, file.filename);
		}

		// Read only regular UTF-8 files, without following symlinks. Walk each
		// component with openat so a package cannot redirect a read outside root.
		static string? read_input (string directory, string filename, out string reason) {
			reason = dgettext (null, "File could not be read as bounded UTF-8 text inside the package directory.");
			if (Path.is_absolute (filename)) {
				return null;
			}
			int fd = Posix.open (directory, Posix.O_RDONLY | Posix.O_DIRECTORY | Posix.O_CLOEXEC);
			if (fd < 0) {
				return null;
			}
			string[] parts = filename.split ("/");
			for (int i = 0; i < parts.length; i++) {
				if (parts[i] == "" || parts[i] == "." || parts[i] == "..") {
					Posix.close (fd);
					return null;
				}
				int flags = Posix.O_RDONLY | Posix.O_NOFOLLOW | Posix.O_NONBLOCK | Posix.O_CLOEXEC;
				if (i < parts.length - 1) {
					flags |= Posix.O_DIRECTORY;
				}
				int next = Posix.openat (fd, parts[i], flags);
				Posix.close (fd);
				fd = next;
				if (fd < 0) {
					return null;
				}
			}
			Posix.Stat info;
			if (Posix.fstat (fd, out info) != 0 || !Posix.S_ISREG (info.st_mode) || info.st_size > 256 * 1024) {
				Posix.close (fd);
				return null;
			}
			uint8[] bytes = new uint8[256 * 1024 + 1];
			int length = 0;
			while (length < bytes.length) {
				ssize_t count = Posix.read (fd, (void*) ((uint8*) bytes + length), bytes.length - length);
				if (count < 0) {
					if (Posix.errno == Posix.EINTR) {
						continue;
					}
					Posix.close (fd);
					return null;
				}
				if (count == 0) {
					break;
				}
				length += (int) count;
			}
			Posix.close (fd);
			if (length > 256 * 1024 || !((string) bytes).validate_len (length)) {
				return null;
			}
			for (int i = 0; i < length; i++) {
				if (bytes[i] == 0) {
					return null;
				}
			}
			return ((string) bytes).substring (0, length);
		}

		// Offline advisory scan of the current files. Existing .SRCINFO is
		// untrusted metadata, not proof that it describes the PKGBUILD exactly.
		public static AurReview from_directory (string directory, AURPackage? pkg = null) {
			string reason;
			string? srcinfo = read_input (directory, ".SRCINFO", out reason);
			var review = pkg == null ? new AurReview (srcinfo, 3, 0.05) : for_package (pkg, srcinfo);
			if (srcinfo != null && srcinfo.strip () == "") {
				reason = dgettext (null, "The .SRCINFO file is empty.");
			}
			if (srcinfo == null || srcinfo.strip () == "") {
				review.skip_file (review.expect_file (".SRCINFO"), reason);
			}
			int total = srcinfo == null ? 0 : srcinfo.length;
			for (int i = 0; i < review.files.length; i++) {
				var file = review.files[i];
				if (file.status != AurReviewFileStatus.PENDING) {
					continue;
				}
				if (i >= 64 || total >= 1024 * 1024) {
					review.skip_file (file, dgettext (null, "Local review input limit reached."));
					continue;
				}
				string? content = read_input (directory, file.filename, out reason);
				if (content == null) {
					review.skip_file (file, reason);
					continue;
				}
				total += content.length;
				if (total > 1024 * 1024) {
					review.skip_file (file, dgettext (null, "Local review input limit reached."));
					continue;
				}
				if (file.filename == "PKGBUILD") {
					// Also inspect literal install assignments: the checked-in
					// .SRCINFO can be absent or stale. Dynamic names stay explicit.
					var install_assignment = /^[ \t]*install[ \t]*=[ \t]*([^;\n]+)/m;
					MatchInfo match;
					var shell = new AurReviewShell ();
					install_assignment.match (shell.mask_data (content, true), 0, out match);
					while (match.matches ()) {
						string value = match.fetch (1).strip ();
						if (value.length >= 2 && ((value[0] == '\'' && value[value.length - 1] == '\'') ||
							(value[0] == '"' && value[value.length - 1] == '"'))) {
							value = value.substring (1, value.length - 2);
						}
						if (value != "") {
							var input = review.expect_file (value);
							if (/[\s$`\\"']/.match (value)) {
								review.skip_file (input, dgettext (null, "Install script expression could not be resolved without executing PKGBUILD."));
							}
						}
						try {
							match.next ();
						} catch (RegexError e) {
							break;
						}
					}
				}
				review.scan_script (file.filename, content);
			}
			return review;
		}

		static Uri? source_uri (string source) {
			int alias_end = source.index_of ("::");
			int scheme_end = source.index_of ("://");
			string url = alias_end >= 0 && (scheme_end < 0 || alias_end < scheme_end)
				? source.substring (alias_end + 2) : source;
			try {
				return Uri.parse (url, UriFlags.NONE);
			} catch (UriError e) {
				return null;
			}
		}
	}
}

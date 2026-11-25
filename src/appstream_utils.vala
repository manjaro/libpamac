/*
 *  pamac-vala
 *
 *  Copyright (C) 2023 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// helpers shared by the appstream and flatpak plugins
namespace Pamac {
	internal const uint PREFERRED_ICON_SIZE = 64;

	internal const string[] MAIN_CATEGORIES = {
		"Photo & Video",
		"Music & Audio",
		"Productivity",
		"Communication & News",
		"Education & Science",
		"Games",
		"Utilities",
		"Development"
	};

	// prefer the exact size, then the smallest bigger one, then the biggest smaller one
	internal bool is_better_icon_size (uint size, uint best_size) {
		if (best_size == PREFERRED_ICON_SIZE) {
			return false;
		}
		if (size >= PREFERRED_ICON_SIZE) {
			return best_size < PREFERRED_ICON_SIZE || size < best_size;
		}
		return best_size < PREFERRED_ICON_SIZE && size > best_size;
	}

	// best cached icon, icons with a scale factor are stored in another directory
	internal unowned AppStream.Icon? get_best_cached_icon (AppStream.Component as_app) {
		unowned AppStream.Icon? best_icon = null;
		unowned GenericArray<AppStream.Icon> as_icons = as_app.get_icons ();
		foreach (unowned AppStream.Icon as_icon in as_icons) {
			if (as_icon.get_kind () != AppStream.IconKind.CACHED || as_icon.get_scale () > 1) {
				continue;
			}
			if (best_icon == null || is_better_icon_size (as_icon.get_height (), best_icon.get_height ())) {
				best_icon = as_icon;
			}
		}
		return best_icon;
	}

	// markdown description, null if there is none
	internal string? get_markdown_description (AppStream.Component as_app) {
		unowned string? description = as_app.get_description ();
		if (description == null) {
			return null;
		}
		try {
			return AppStream.markup_convert (description, AppStream.MarkupKind.MARKDOWN);
		} catch (Error e) {
			warning (e.message);
			return null;
		}
	}

	internal unowned string? get_first_desktop_launchable (AppStream.Component as_app) {
		unowned AppStream.Launchable? as_launchable = as_app.get_launchable (AppStream.LaunchableKind.DESKTOP_ID);
		if (as_launchable != null) {
			unowned GenericArray<string> entries = as_launchable.get_entries ();
			if (entries.length > 0) {
				return entries[0];
			}
		}
		return null;
	}

	// lowercased tokens, without empty ones (e.g. from consecutive spaces)
	internal string[] get_search_tokens (string[] search_terms) {
		string[] tokens = {};
		foreach (unowned string term in search_terms) {
			if (term != "") {
				tokens += term.down ();
			}
		}
		return tokens;
	}

	// apps are indexed with stemmed words in the current locale
	// (e.g. "disk" for "Disks"), search terms have to be processed the same way
	internal string[] get_stemmed_search_tokens (AppStream.Pool search_pool, string[] tokens) {
		string[] stemmed_tokens = search_pool.build_search_tokens (string.joinv (" ", tokens));
		if (stemmed_tokens.length == 0) {
			// e.g. only stop words: keep the given tokens
			return tokens;
		}
		return stemmed_tokens;
	}

	internal bool id_matches_all (string id, string[] tokens) {
		string id_down = id.down ();
		foreach (unowned string token in tokens) {
			if (!(token in id_down)) {
				return false;
			}
		}
		return true;
	}

	// map freedesktop categories to pamac ones
	internal unowned string? get_main_category (string cat) {
		switch (cat) {
			case "Photography":
			case "ImageProcessing":
			case "Graphics":
			case "Video":
			case "VectorGraphics":
			case "2DGraphics":
			case "3DGraphics":
				return "Photo & Video";
			case "Audio":
			case "Music":
			case "Midi":
			case "Mixer":
			case "Multimedia":
				return "Music & Audio";
			case "WebBrowser":
			case "Email":
			case "Office":
			case "Calculator":
			case "Calendar":
			case "Clock":
			case "ContactManagement":
			case "Dictionary":
			case "Documentation":
			case "Finance":
			case "FlowChart":
			case "Presentation":
			case "Productivity":
			case "Spreadsheet":
			case "WordProcessor":
			case "Publishing":
				return "Productivity";
			case "Network":
			case "Chat":
			case "News":
			case "Feed":
			case "Communication":
			case "InstantMessaging":
			case "IRCClient":
			case "Telephony":
			case "VideoConference":
				return "Communication & News";
			case "Education":
			case "Science":
			case "Astronomy":
			case "Chemistry":
			case "ComputerScience":
			case "Electricity":
			case "Electronics":
			case "Physics":
			case "Engineering":
			case "Geography":
			case "Geoscience":
			case "Languages":
			case "Literature":
			case "Maps":
			case "Math":
			case "NumericalAnalysis":
				return "Education & Science";
			case "Games":
			case "Game":
			case "ActionGame":
			case "ArcadeGame":
			case "BlocksGame":
			case "BoardGame":
			case "LogicGame":
			case "StrategyGame":
			case "RolePlaying":
			case "AdventureGame":
			case "CardGame":
			case "KidsGame":
			case "Emulator":
				return "Games";
			case "Utility":
			case "Monitor":
			case "Accessibility":
			case "Archiving":
			case "Compression":
			case "ConsoleOnly":
			case "Core":
			case "DesktopSettings":
			case "DiscBurning":
			case "Settings":
			case "FileManager":
			case "Filesystem":
			case "FileTools":
			case "PackageManager":
			case "FileTransfer":
			case "HardwareSettings":
				return "Utilities";
			case "Development":
			case "IDE":
			case "Building":
			case "Construction":
			case "Database":
			case "DataVisualization":
			case "Debugger":
			case "GUIDesigner":
			case "Java":
			case "WebDevelopment":
				return "Development";
			default:
				return null;
		}
	}
}

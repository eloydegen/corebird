using Gtk;

// TODO: Rework the author database
// TODO: Make tweet loading in the main-timeline work!
class Tweet : GLib.Object{
	public string id;
	public bool retweeted = false;
	public bool favorited = false;
	public string text;
	public int user_id;
	public string user_name;
	public string retweeted_by;
	public bool is_retweet;
	public Gdk.Pixbuf avatar {get; set;}
	public string time_delta = "-1s";
	public string avatar_url;
	public string avatar_name;
	public string screen_name;

	public Tweet(){
		this.avatar = Twitter.no_avatar;

	}

	public void load_avatar(){
		if (Twitter.avatars.has_key(avatar_name))
			this.avatar = Twitter.avatars.get(avatar_name);
		else{
			string path = "assets/avatars/%s".printf(avatar_name);
			if(FileUtils.test(path, FileTest.EXISTS)){
				try{
					Twitter.avatars.set(avatar_name,
				    	new Gdk.Pixbuf.from_file(path));
				}catch(GLib.Error e){
					warning("Error while loading avatar from database: %s", e.message);
				}
				this.avatar = Twitter.avatars.get(avatar_name);
			}
		}
	}

	public bool has_avatar(){
		return this.avatar != Twitter.no_avatar;
	}

	/**
	 * Fills all the data of this tweet from Json data.
	 */
	public void load_from_json(Json.Object status, GLib.DateTime now,
	            	out string created_at, out int64 added_to_stream){
		Json.Object user    = status.get_object_member("user");
		this.text           = status.get_string_member("text");
		this.favorited      = status.get_boolean_member("favorited");
		this.retweeted      = status.get_boolean_member("retweeted");
		this.id             = status.get_string_member("id_str");
		this.user_name      = user.get_string_member("name");
		this.user_id        = (int)user.get_int_member("id");
		this.screen_name    = user.get_string_member("screen_name");
		created_at          = status.get_string_member("created_at");
		string display_name = user.get_string_member("screen_name");
		added_to_stream     = Utils.parse_date(created_at).to_unix();
		this.avatar_url     = user.get_string_member("profile_image_url");



		var entities = status.get_object_member("entities");
		if (status.has_member("retweeted_status")){
			Json.Object rt      = status.get_object_member("retweeted_status");
			Json.Object rt_user = rt.get_object_member("user");
			this.is_retweet   = true;
			this.retweeted_by = user.get_string_member("name");
			this.text         = rt.get_string_member("text");
			// this.id           = rt.get_string_member("id_str");
			// this.rt_id 		  = rt.get_string_member("id_str");
			this.user_name    = rt_user.get_string_member ("name");
			this.avatar_url   = rt_user.get_string_member("profile_image_url");
			this.user_id      = (int)rt_user.get_int_member("id");
			this.screen_name  = rt_user.get_string_member("screen_name");
			created_at        = rt.get_string_member("created_at");
			display_name      = rt_user.get_string_member("screen_name");
			entities 		  = rt.get_object_member("entities");
		}
		this.avatar_name = Utils.get_avatar_name(this.avatar_url);



		// 'Resolve' the used URLs
		
		var urls = entities.get_array_member("urls");
		urls.foreach_element((arr, index, node) => {
			var url = node.get_object();
			string expanded_url = url.get_string_member("expanded_url");
			// message("Text: %s, expanded: %s", this.text, expanded_url);	
			expanded_url = expanded_url.replace("&", "&amp;");
			this.text = this.text.replace(url.get_string_member("url"),
			    expanded_url);
		});

		// The same with media
		if(entities.has_member("media")){
			var medias = entities.get_array_member("media");
			medias.foreach_element((arr, index, node) => {
				var url = node.get_object();
				string expanded_url = "https://"+url.get_string_member("display_url");
				this.text = this.text.replace(url.get_string_member("url"),
				    expanded_url);
			});
		}




		GLib.DateTime dt = Utils.parse_date(created_at);
		this.time_delta  = Utils.get_time_delta(dt, now);


		//TODO: Since the avatar gets loaded asynchronously, it's possible that the same avatar gets loaded
		//      several times. Introduce some kind of lock here.

		this.load_avatar();
		if(!this.has_avatar()){
			File av = File.new_for_uri(this.avatar_url);
			File dest = File.new_for_path("assets/avatars/%s".printf(this.avatar_name));
			av.copy_async.begin(dest, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, null, (obj, res) => {
				try{
					av.copy_async.end(res);
				}catch(GLib.Error e){
					warning("Couldn't download avatar for %s: %s", this.screen_name, e.message);
				}
				message("Loaded Avatar for %s", this.screen_name);
				this.load_avatar();
				//Make the corners round
				// TODO: How to write it as gif/jpg file?
				// Cairo.ImageSurface frame = new Cairo.ImageSurface.from_png("assets/frame.png");
				// Cairo.ImageSurface result = new Cairo.ImageSurface(Cairo.Format.ARGB32, 48, 48);
				// surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 48, 48);
				// Cairo.Context context = new Cairo.Context(result);
				// context.set_source_surface(surface, 0, 0);
				// context.rectangle(0, 0, 48,48);
				// context.fill();


				// context.set_operator(Cairo.Operator.DEST_OUT);
				// context.set_source_surface(frame, 0, 0);
				// context.rectangle(0, 0, 48, 48);
				// context.paint();
				
				// context.fill();

				// result.write_to_png("avatar_changed.png");
			});


		}
	}


	public static void cache(Tweet t, string created_at, int64 added_to_stream, int type){
		// Check the tweeter's details and update them if necessary
		try{
			SQLHeavy.Query author_query = new SQLHeavy.Query(Corebird.db,
			"SELECT `id`, `screen_name`, `avatar_url` FROM `people`
			WHERE `id`='%d';".printf(t.user_id));
			SQLHeavy.QueryResult author_result = author_query.execute();
			if (author_result.finished){
				//The author is not in the DB so we insert him
				message("Inserting new author %s", t.screen_name);
				SQLHeavy.Query q = new SQLHeavy.Query(Corebird.db,
				"INSERT INTO `people`(id,name,screen_name,avatar_url,avatar_name) VALUES ('%d', 
				'%s', '%s', '%s', '%s');".printf(t.user_id, t.user_name,
				t.screen_name, t.avatar_url, t.avatar_name));
				q.execute();
			}else{
				string old_avatar = author_result.fetch_string(2);
				if (old_avatar != t.avatar_url){
					Corebird.db.execute("UPDATE `people` SET `avatar_url`='%s';", t.avatar_url);
				}
				if (t.user_name != author_result.fetch_string(1)){
					Corebird.db.execute("UPDATE `people` SET `screen_name`='%s';", t.user_name);
				}
			}
		}catch(SQLHeavy.Error e){
			warning("Error while updating author: %s", e.message);
		}
		
		
		// Insert tweet into cache table
		try{
			SQLHeavy.Query cache_query = new SQLHeavy.Query(Corebird.db,
			"INSERT INTO `cache`(`id`, `text`,`user_id`, `user_name`, `is_retweet`,
			                     `retweeted_by`, `retweeted`, `favorited`, `created_at`, `added_to_stream`,
			                     `avatar_name`, `screen_name`, `type`) 
			VALUES (:id, :text, :user_id, :user_name, :is_retweet, :retweeted_by,
			        :retweeted, :favorited, :created_at, :added_to_stream, :avatar_name,
			        :screen_name, :type);");					
			cache_query.set_string(":id", t.id);
			cache_query.set_string(":text", t.text);
			cache_query.set_int(":user_id", t.user_id);
			cache_query.set_string(":user_name", t.user_name);
			cache_query.set_int(":is_retweet", t.is_retweet ? 1 : 0);
			cache_query.set_string(":retweeted_by", t.retweeted_by);
			cache_query.set_int(":retweeted", t.retweeted ? 1 : 0);
			cache_query.set_int(":favorited", t.favorited ? 1 : 0);
			cache_query.set_string(":created_at", created_at);
			cache_query.set_int64(":added_to_stream", added_to_stream);
			cache_query.set_string(":avatar_name", t.avatar_name);
			cache_query.set_string(":screen_name", t.screen_name);
			cache_query.set_int(":type", type); // 1 = normal tweet
			cache_query.execute();
		}catch(SQLHeavy.Error e){
			error("Error while caching tweet: %s", e.message);
		}
	}



	private static GLib.Regex? link_regex    = null;
	public static string replace_links(string text){
		if(link_regex == null){
			link_regex = new GLib.Regex("http[s]{0,1}:\\/\\/[a-zA-Z\\_.\\+\\?\\/#=&;\\-0-9%,]+",
			                            RegexCompileFlags.OPTIMIZE);
		}
		string real_text = text;
		try{
			MatchInfo mi;
			if (link_regex.match(real_text, 0, out mi)){
				do{

					string link = mi.fetch(0);
					if (link.length > 25){
						if(link.has_prefix("http://"))
							link = link.substring(7);
						else //https
							link = link.substring(8);

						if(link.has_prefix("www."))
							link = link.substring(4);

						if(link.length > 25){
							link = link.substring(0, 25);
							link += "…";
						}

					}
					real_text = real_text.replace(mi.fetch(0),
						"<a href='%s'>%s</a>".printf(mi.fetch(0), link));
				}while(mi.next());
			}
	
		}catch(GLib.RegexError e){
			warning("Error while applying regexes: %s", e.message);
		}

		return real_text;
	}
}
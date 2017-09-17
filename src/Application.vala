/*
* Copyright (c) 2017 José Amuedo (https://github.com/spheras)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/

/**
* @class
* The Main Application
*/
public class DesktopFolderApp : Granite.Application {

    /** File Monitor of desktop folder */
    private FileMonitor monitor=null;

    /** List of folder owned by the application */
    private List<DesktopFolder.FolderManager> folders=new List<DesktopFolder.FolderManager>();

    construct {
        /* Needed by Glib.Application */
        this.application_id = DesktopFolder.APP_ID;  //Ensures an unique instance.
        this.flags = ApplicationFlags.FLAGS_NONE;

        /* Needed by Granite.Application */
        this.program_name = _(DesktopFolder.APP_TITLE);
        this.exec_name = DesktopFolder.APP_NAME;
        this.build_version = DesktopFolder.VERSION;
    }

    /**
    * @constructor
    */
    public DesktopFolderApp () {
        Object (application_id: "org.spheras.desktopfolder",
        flags: ApplicationFlags.FLAGS_NONE);
    }

    /**
    * @name activate
    * @override
    * @description activate life cycle
    */
    protected override void activate () {
        base.activate ();
        debug("activate event");
        //we'll init the app in the activate event
        init();
    }

    /**
    * @name startup
    * @override
    * @description startup life cycle
    */
    public override void startup () {
        base.startup ();
        debug("startup event");
    }

    /**
    * @name init
    * @description initialization of the application
    */
    private void init(){
        //only one app at a time
        if (get_windows().length () > 0) {
            get_windows().data.present ();
            return;
        }

        create_shortchut();

        //initializing the clipboard manager
        DesktopFolder.Clipboard.ClipboardManager.get_for_display ();

        //providing css styles
        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("org/spheras/desktopfolder/Application.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        //quit action
        /*
        var quit_action = new SimpleAction ("quit", null);
        add_action (quit_action);
        add_accelerator ("<Control>q", "app.quit", null);
        quit_action.activate.connect (() => {
            if (app_window != null) {
                app_window.destroy ();
            }
        });
        */

        //we start creating the folders found at the desktop folder
        this.sync_folders();
        this.monitor_desktop();
    }

    /**
    * @name get_app_folder
    * @description return the path where the app search folders to be created (the desktop folder)
    * @return string the absolute path directory
    */
    public static string get_app_folder (){
        return Environment.get_home_dir ()+"/Desktop";
    }

    /**
    * @name sync_folders
    * @description create as many folder windows as the desktop folder founds
    */
    private void sync_folders () {
        try {
            var base_path=DesktopFolderApp.get_app_folder();
            var directory = File.new_for_path (base_path);
            var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);

            FileInfo file_info;
            List<DesktopFolder.FolderManager> updated_list=new List<DesktopFolder.FolderManager>();
            int totalFolders=0;
            while ((file_info = enumerator.next_file ()) != null) {
                string name=file_info.get_name();
                File file = File.new_for_commandline_arg (base_path+"/"+name);
                FileType type = file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if(type==FileType.DIRECTORY){
                    totalFolders++;
                    //maybe this is an existent already monitored folder
                    DesktopFolder.FolderManager fm=this.find_by_name(name);
                    if(fm==null){
                        //we've found a directory, let's create a desktop-folder window
                        fm=new DesktopFolder.FolderManager(this, name);
                    }else{
                        this.folders.remove(fm);
                    }
                    updated_list.append(fm);
                }else{
                    //nothing
                    //we only deal with folders to be shown
                }
            }

            //finally we close any other not existent folder
            for(int i=0;i<this.folders.length();i++){
                DesktopFolder.FolderManager fm=this.folders.nth(i).data;
                fm.close();
            }
            this.folders=updated_list.copy();

            if(totalFolders==0){
                DirUtils.create(DesktopFolderApp.get_app_folder()+"/"+DesktopFolder.Lang.APP_FIRST_PANEL,0755);
                this.sync_folders();
            }
        } catch (Error e) {
            //error! ??
            stderr.printf ("Error: %s\n", e.message);
            DesktopFolder.Util.show_error_dialog("Error",e.message);
        }
    }

    /**
    * @name find_by_name
    * @description find a foldermanager managed by its name
    * @param string folder_name the name of the folder to find
    * @return FolderManager the Folder found or null if none
    */
    private DesktopFolder.FolderManager? find_by_name(string folder_name){
        for(int i=0;i<this.folders.length();i++){
            DesktopFolder.FolderManager fm=this.folders.nth(i).data;
            if(fm.get_folder_name()==folder_name){
                return fm;
            }
        }
        return null;
    }

    /**
    * @name exist_manager
    * @description check if the folder_name is being monitored or not
    * @return bool true->yes, it is being monitored
    */
    public bool exist_manager(string folder_name){
        for(int i=0;i<this.folders.length();i++){
            DesktopFolder.FolderManager fm=this.folders.nth(i).data;
            if(fm.get_folder_name()==folder_name){
                return true;
            }
        }
        return false;
    }

    /**
    * @name monitor_desktop
    * @description monitor the desktop folder
    */
    private void monitor_desktop(){
        try{
            if(this.monitor!=null){
                //if we have an existing monitor, we cancel it before to monitor again
                this.monitor.cancel();
            }
            var basePath=DesktopFolderApp.get_app_folder();
            File directory = File.new_for_path (basePath);
            this.monitor = directory.monitor_directory (FileMonitorFlags.SEND_MOVED,null);
            this.monitor.rate_limit = 100;
            debug("Monitoring: %s\n", directory.get_path ());
            this.monitor.changed.connect(this.desktop_changed);
        } catch (Error e) {
            stderr.printf ("Error: %s\n", e.message);
            DesktopFolder.Util.show_error_dialog("Error",e.message);
        }
    }

    /**
    * @name desktop_changed
    * @description we received an event of the monitor that indicates a change
    * @see changed signal of FileMonitor (https://valadoc.org/gio-2.0/GLib.FileMonitor.changed.html)
    */
    private void desktop_changed (GLib.File src, GLib.File? dest, FileMonitorEvent event) {
        //something changed at the desktop folder
        debug("Desktop - Change Detected");
        //new content inside
        var file_type= src.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
        if (file_type==FileType.DIRECTORY || !src.query_exists()){
            //new directory or removed, we need to synchronize
            //removed directory
            this.sync_folders();
        }
    }

    /**
    * @name clear_all
    * @description close all the folders launched
    */
    protected void clear_all(){
        for(int i=0;i<this.folders.length();i++){
            DesktopFolder.FolderManager fm=this.folders.nth(i).data;
            fm.close();
        }
        this.folders=new List<DesktopFolder.FolderManager>();
    }

    /**
    * Main application
    */
    public static int main (string[] args) {
        if(args.length>1 && args[1].up()==DesktopFolder.PARAM_SHOW_DESKTOP.up()){
            minimize_all(args);
            return 0;
        }else{
            var app = new DesktopFolderApp ();
            return app.run (args);
        }
    }

    /**
    * @name minimize_all
    * @description minimize all windows
    * @param args string[] the list of args to initialize Gdk
    */
    private static void minimize_all(string[] args){
        Gdk.init(ref args);
        Wnck.Screen screen = Wnck.Screen.get_default();
        while(Gtk.events_pending()){
            Gtk.main_iteration();
        }

        unowned List<Wnck.Window> windows = screen.get_windows();

        foreach(Wnck.Window w in windows){
            w.minimize();
        }
    }

    /**
    * @name create_shortchut
    * @description create a short cut SUPER-D at the system shortcuts to minimize all windows
    */
    private static void create_shortchut(){
        string path="/usr/bin/"; //we expect to have the command at the path
        Pantheon.Keyboard.Shortcuts.CustomShortcutSettings.init();
        var shortcut = new Pantheon.Keyboard.Shortcuts.Shortcut (100, Gdk.ModifierType.SUPER_MASK );
        string command_conflict="";
        string relocatable_schema_conflict="";
        if (!Pantheon.Keyboard.Shortcuts.CustomShortcutSettings.shortcut_conflicts(shortcut, out command_conflict,
             out relocatable_schema_conflict)) {

            debug("registering hotkey!");
            var relocatable_schema = Pantheon.Keyboard.Shortcuts.CustomShortcutSettings.create_shortcut ();
            Pantheon.Keyboard.Shortcuts.CustomShortcutSettings.edit_command ((string) relocatable_schema,
                path + "org.spheras.desktopfolder "+ DesktopFolder.PARAM_SHOW_DESKTOP);
            Pantheon.Keyboard.Shortcuts.CustomShortcutSettings.edit_shortcut ((string) relocatable_schema,
                shortcut.to_gsettings ());
        }
    }
}

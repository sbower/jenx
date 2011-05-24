#
#  AppDelegate.rb
#  jenx
#
#  Created by Trent Kocurek on 5/18/11.
#  Copyright 2011 Urban Coding. Released under the MIT license.
#

require 'rubygems'
require 'json'
require 'open-uri'
require 'net/http'

class Jenx
    attr_accessor :menu, :status_menu_item
    
    def awakeFromNib
        @initial_load = true
        
        @status_bar = NSStatusBar.systemStatusBar
        @jenx_item = @status_bar.statusItemWithLength(NSVariableStatusItemLength)
        @jenx_item.setHighlightMode(true)
        @jenx_item.setMenu(@menu)
        
        JenxPreferences::setup_defaults
        
        @preferences = JenxPreferences.sharedInstance
        
        initialize_menu_ui_items
        
        register_observers
    end
    
    def ensure_connection(sender)
        if @initial_load
            @status_menu_item.setTitle("Refreshing...")
        else
            @status_menu_item.setTitle("Connecting...")
        end
        
        if JenxConnection.new(@preferences.build_server_url).is_connected?
            get_builds
        else
            handle_broken_connection(ERROR_SERVER_CANNOT_BE_CONTACTED)
        end
    end
    
    def get_builds
        if @refresh_timer.nil? || !@refresh_timer.isValid
            @refresh_timer = NSTimer.scheduledTimerWithTimeInterval(@preferences.refresh_time, target:self, selector:"ensure_connection:", userInfo:nil, repeats:true)
        end
        fetch_current_build_status
    end
    
    def fetch_current_build_status
        begin
            @all_projects = JSON.parse(open(@preferences.build_server_url + JENX_API_URI).string)
            
            status_color = ""
            @all_projects['jobs'].each do |project| 
                status_color = project['color'] if project['name'] == @preferences.default_project
            end
            
            @status_menu_item.setTitle(get_current_status_for(status_color))
            @jenx_item.setImage(@app_icon)
            
            load_projects
        rescue Exception => e
            NSLog(e.message)
        end
    end
    
    def load_projects
        if @initial_load
            @all_projects['jobs'].each_with_index do |project, index|
                if index < @preferences.num_menu_projects
                    project_menu_item = NSMenuItem.alloc.init
                    project_menu_item.setTitle(" " + project['name'])
                    project_menu_item.setToolTip(project['url'])
                    project_menu_item.setEnabled(true)
                    project_menu_item.setIndentationLevel(1)
                    project_menu_item.setImage(get_current_status_icon_for(project['color']))
                    project_menu_item.setAction("open_web_interface_for:")
                    @jenx_item.menu.insertItem(project_menu_item, atIndex:index + JENX_STARTING_PROJECT_MENU_INDEX)
                end
            end
            
            view_all_menu_item = NSMenuItem.alloc.init
            view_all_menu_item.setTitle("View all projects..")
            view_all_menu_item.setToolTip(@preferences.build_server_url)
            view_all_menu_item.setIndentationLevel(1)
            view_all_menu_item.setAction("open_web_interface_for:")
            @jenx_item.menu.insertItem(view_all_menu_item, atIndex:@preferences.num_menu_projects + JENX_STARTING_PROJECT_MENU_INDEX)
            
            @initial_load = false
        else
            @all_projects['jobs'].each_with_index do |project, index| 
                if index < @preferences.num_menu_projects
                    project_menu_item = @jenx_item.menu.itemAtIndex(index + JENX_STARTING_PROJECT_MENU_INDEX)
                    project_menu_item.setImage(get_current_status_icon_for(project['color']))
                end
            end
        end
    end
    
    def handle_broken_connection(error_type)
        @refresh_timer.invalidate if @refresh_timer
        @jenx_item.setImage(@build_failure_icon)
        
        if error_type == ERROR_NO_INTERNET_CONNECTION
            @status_menu_item.setTitle("No internet connection...")
            @status_menu_item.setToolTip("No internet connection...")
        else
            @status_menu_item.setTitle("Connection to build server cannot be established...")
            @status_menu_item.setToolTip("Connection to build server cannot be established...")
        end
    end
    
    #actions
    def open_web_interface_for(sender)
        project_url = NSURL.alloc.initWithString(sender.toolTip)
        workspace = NSWorkspace.sharedWorkspace
        workspace.openURL(project_url)
    end
    
    def show_preferences_window(sender)
        NSApplication.sharedApplication.activateIgnoringOtherApps(true)
        PreferencesController.sharedController.showWindow(sender)
    end
    
    private
    
        def initialize_menu_ui_items
            @app_icon = NSImage.imageNamed('app.tiff')
            @connecting_icon = NSImage.imageNamed('connecting.tiff')
            
            @build_success_icon = NSImage.imageNamed('build_success.tiff')
            @build_failure_icon = NSImage.imageNamed('build_failure.tiff')
            @build_initiated_icon = NSImage.imageNamed('build_initiated.tiff')
        end
    
        def register_observers
            notification_center = NSNotificationCenter.defaultCenter
            notification_center.addObserver(
               self,
               selector:"ensure_connection:",
               name:NOTIFICATION_ADDED_SERVER_URL,
               object:nil
            )
            
            notification_center.addObserver(
               self,
               selector:"ensure_connection:",
               name:NSApplicationDidFinishLaunchingNotification,
               object:nil
            )
        end
    
        def get_current_status_icon_for(color)
            case color
                when "red"
                    return @build_failure_icon
                when "blue_anime"
                    return @build_initiated_icon
                else
                    return @build_success_icon
            end
        end
        
        def get_current_status_for(color)
            if @preferences.default_project.empty?
                return "No default project set"
            end
            
            case color
                when ""
                return "Could not retrieve status"
                when "red"
                return @preferences.default_project + ": Broken"
                when "blue_anime"
                return @preferences.default_project + ": Building"
                else
                return @preferences.default_project + ": Stable"
            end
        end
end


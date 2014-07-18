//
//  Copyright (C) 2011-2012 Jaap Broekhuizen
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

public class Maya.View.EventEdition.LocationPanel : Gtk.Grid {
    private EventDialog parent_dialog;

    private Gtk.SearchEntry location_entry;

    private GtkChamplain.Embed champlain_embed;
    private Maya.Marker point;
     // Only set the geo property if map_selected is true, this is a smart behavior!
    private bool map_selected = false;

    public LocationPanel (EventDialog parent_dialog) {
        this.parent_dialog = parent_dialog;

        margin_left = 12;
        margin_right = 12;
        set_row_spacing (6);
        set_column_spacing (12);
        set_sensitive (parent_dialog.can_edit);

        var location_label = Maya.View.EventDialog.make_label (_("Location:"));
        location_entry = new Gtk.SearchEntry ();
        location_entry.placeholder_text = _("John Smith OR Example St.");
        location_entry.hexpand = true;
        location_entry.activate.connect (() => {compute_location.begin (location_entry.text);});
        attach (location_label, 0, 0, 1, 1);
        attach (location_entry, 0, 1, 1, 1);

        champlain_embed = new GtkChamplain.Embed ();
        var view = champlain_embed.champlain_view;
        var marker_layer = new Champlain.MarkerLayer.full (Champlain.SelectionMode.SINGLE);
        view.add_layer (marker_layer);

        attach (champlain_embed, 0, 2, 1, 1);

        // Load the location
        point = new Maya.Marker ();
        point.draggable = parent_dialog.can_edit;
        point.drag_finish.connect (() => {
            map_selected = true;
        });

        if (parent_dialog.ecal != null) {
            string location;
            parent_dialog.ecal.get_location (out location);
            if (location != null)
                location_entry.text = location;

            iCal.GeoType? geo;
            parent_dialog.ecal.get_geo (out geo);
            bool need_relocation = true;
            if (geo != null) {
                if (geo.latitude >= Champlain.MIN_LATITUDE && geo.longitude >= Champlain.MIN_LONGITUDE &&
                    geo.latitude <= Champlain.MAX_LATITUDE && geo.longitude <= Champlain.MAX_LONGITUDE) {
                    need_relocation = false;
                    point.latitude = geo.latitude;
                    point.longitude = geo.longitude;
                    if (geo.latitude == 0 && geo.longitude == 0)
                        need_relocation = true;
                }
            }
            if (need_relocation == true) {
                if (location != null && location != "") {
                    compute_location.begin (location_entry.text);
                } else {
                    // A little hacky but seems to work as expected (search for the timezone position)
                    compute_location.begin (E.Cal.util_get_system_timezone_location ());
                }
            }
        }
        view.zoom_level = 8;
        view.center_on (point.latitude, point.longitude);
        marker_layer.add_marker (point);
    }

    /**
     * Save the values in the dialog into the component.
     */
    public void save () {
        // Save the location
        unowned iCal.Component comp = parent_dialog.ecal.get_icalcomponent ();
        string location = location_entry.text;

        comp.set_location (location);
        if (map_selected == true) {
            // First, clear the geo
            int count = comp.count_properties (iCal.PropertyKind.GEO);

            for (int i = 0; i < count; i++) {
                unowned iCal.Property remove_prop = comp.get_first_property (iCal.PropertyKind.GEO);

                comp.remove_property (remove_prop);
            }

            // Add the comment
            var property = new iCal.Property (iCal.PropertyKind.GEO);
            iCal.GeoType geo = {0, 0};
            geo.latitude = (float)point.latitude;
            geo.longitude = (float)point.longitude;
            property.set_geo (geo);
            comp.add_property (property);
        }
    }

    private async void compute_location (string loc) {
        SourceFunc callback = compute_location.callback;
        Threads.add (() => {
            var forward = new Geocode.Forward.for_string (loc);
            try {
                forward.set_answer_count (10);
                var places = forward.search ();
                foreach (var place in places) {
                    point.latitude = place.location.latitude;
                    point.longitude = place.location.longitude;
                    champlain_embed.champlain_view.go_to (point.latitude, point.longitude);
                }

                if (loc == location_entry.text)
                    map_selected = true;

                location_entry.has_focus = true;
            } catch (Error error) {
                debug (error.message);
            }

            Idle.add ((owned) callback);
        });

        yield;
    }
}

public class Maya.Marker : Champlain.Marker {
    public Marker () {
        try {
            Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file ("%s/LocationMarker.svg".printf (Build.PKGDATADIR));
            Clutter.Image image = new Clutter.Image ();
            image.set_data (pixbuf.get_pixels (),
                          pixbuf.has_alpha ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888,
                          pixbuf.width,
                          pixbuf.height,
                          pixbuf.rowstride);
            content = image;
            set_size (pixbuf.width, pixbuf.height);
            translation_x = -pixbuf.width/2;
            translation_y = -pixbuf.height;
        } catch (Error e) {
            critical (e.message);
        }
    }
}
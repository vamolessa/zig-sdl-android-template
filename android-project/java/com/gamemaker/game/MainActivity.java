package com.gamemaker.game;

import org.libsdl.app.SDLActivity; 

public class MainActivity extends SDLActivity {
    @Override
    protected String getMainFunction() {
        return "SDL_main";
    }

    @Override
    protected String[] getLibraries() {
        return new String[] {
            "hidapi",
            "SDL2",
            // "SDL2_image",
            // "SDL2_mixer",
            // "SDL2_net",
            // "SDL2_ttf",
            "main"
        };
    }
}


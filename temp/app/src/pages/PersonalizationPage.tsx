import { useState } from 'react';
import { motion } from 'framer-motion';
import { Volume2, VolumeX, ChevronRight } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';

const themes = [
  { id: 'default', name: 'Classic', bg: 'bg-[#F5F5F0]', border: 'border-[#D4A574]' },
  { id: 'nature', name: 'Nature', bg: 'bg-[#E8F5E9]', border: 'border-[#4CAF50]' },
  { id: 'dark', name: 'Dark', bg: 'bg-[#2D2D3A]', border: 'border-[#5B5FC7]' },
];

const avatars = [
  { id: 'inku', src: '/characters/inku-main.png', name: 'Inku' },
  { id: 'boy', src: '/characters/avatar-boy.png', name: 'Alex' },
  { id: 'dog', src: '/characters/avatar-dog.png', name: 'Buddy' },
  { id: 'girl', src: '/characters/avatar-girl.png', name: 'Sam' },
  { id: 'robot', src: '/characters/avatar-robot.png', name: 'Robo' },
  { id: 'toaster', src: '/characters/avatar-toaster.png', name: 'Toast' },
];

export default function PersonalizationPage({ onNext, state, setState }: PageProps) {
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [selectedTheme, setSelectedTheme] = useState(state.selectedTheme || 'default');
  const [selectedAvatar, setSelectedAvatar] = useState(state.selectedAvatar || 'inku');

  const handleContinue = () => {
    setState(prev => ({
      ...prev,
      selectedTheme,
      selectedAvatar,
    }));
    onNext();
  };

  return (
    <div className="h-full flex flex-col bg-[#0D8A6A] relative overflow-hidden">
      {/* Status Bar */}
      <div className="flex items-center justify-between px-6 pt-3 pb-2">
        <span className="text-white text-sm font-semibold">22:30</span>
        <div className="flex items-center gap-1">
          <div className="flex gap-0.5">
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white/40 rounded-sm" />
          </div>
          <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 3C7.46 3 3.34 4.78.29 7.67c-.18.18-.29.43-.29.71 0 .28.11.53.29.71l11 11c.39.39 1.02.39 1.41 0l11-11c.18-.18.29-.43.29-.71 0-.28-.11-.53-.29-.71C20.66 4.78 16.54 3 12 3z"/>
          </svg>
          <div className="flex items-center gap-1 bg-white/20 rounded-md px-1.5 py-0.5">
            <span className="text-white text-xs font-semibold">98</span>
          </div>
        </div>
      </div>

      {/* Speaker Toggle */}
      <button
        onClick={() => setSoundEnabled(!soundEnabled)}
        className="absolute top-14 left-4 w-10 h-10 rounded-full bg-white/20 flex items-center justify-center backdrop-blur-sm z-10"
      >
        {soundEnabled ? (
          <Volume2 className="w-5 h-5 text-white" />
        ) : (
          <VolumeX className="w-5 h-5 text-white" />
        )}
      </button>

      {/* Progress Dots */}
      <div className="flex justify-center gap-2 mt-2">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={`h-1 rounded-full transition-all duration-300 ${
              i === 2 ? 'w-8 bg-white' : 'w-8 bg-white/30'
            }`}
          />
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-6 overflow-y-auto">
        {/* Title */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="text-3xl font-bold text-white text-center mb-2"
        >
          Your Inku, Your Way <span className="text-2xl">🎨</span>
        </motion.h1>

        {/* Theme Selection */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="mb-6"
        >
          <p className="text-white/80 text-center mb-4">Pick your favorite mood</p>
          <div className="flex gap-3 justify-center">
            {themes.map((theme) => (
              <motion.button
                key={theme.id}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => setSelectedTheme(theme.id)}
                className={`relative w-24 h-32 rounded-2xl overflow-hidden shadow-lg transition-all ${
                  selectedTheme === theme.id ? 'ring-4 ring-white scale-105' : ''
                }`}
              >
                <div className={`absolute inset-0 ${theme.bg}`} />
                <div className="absolute inset-2 bg-white/50 rounded-xl flex flex-col items-center justify-center p-2">
                  <div className="w-8 h-8 rounded-full bg-[#0D8A6A] mb-2" />
                  <div className="w-full h-2 bg-gray-300 rounded mb-1" />
                  <div className="w-3/4 h-2 bg-gray-300 rounded" />
                </div>
              </motion.button>
            ))}
          </div>
        </motion.div>

        {/* Avatar Selection */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="flex-1"
        >
          <p className="text-white/80 text-center mb-4">Pick an Inku Avatar..or upload your own!</p>
          <div className="flex gap-4 overflow-x-auto pb-4 hide-scrollbar scroll-snap-x">
            {avatars.map((avatar, index) => (
              <motion.button
                key={avatar.id}
                initial={{ x: 50, opacity: 0 }}
                animate={{ x: 0, opacity: 1 }}
                transition={{ delay: 0.3 + index * 0.1 }}
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.9 }}
                onClick={() => setSelectedAvatar(avatar.id)}
                className={`flex-shrink-0 scroll-snap-center ${
                  selectedAvatar === avatar.id ? 'scale-110' : ''
                }`}
              >
                <div
                  className={`w-20 h-20 rounded-2xl overflow-hidden shadow-lg transition-all ${
                    selectedAvatar === avatar.id
                      ? 'ring-4 ring-white'
                      : 'opacity-70'
                  }`}
                >
                  <img
                    src={avatar.src}
                    alt={avatar.name}
                    className="w-full h-full object-cover"
                  />
                </div>
                <p className="text-white text-xs text-center mt-2">{avatar.name}</p>
              </motion.button>
            ))}
          </div>
        </motion.div>
      </div>

      {/* CTA Button */}
      <div className="px-6 pb-8">
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.5 }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={handleContinue}
          className="w-full bg-[#1A1A2E] text-white py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2"
        >
          I'll Make It Mine <span className="text-xl">🎨</span>
          <ChevronRight className="w-5 h-5" />
        </motion.button>
      </div>
    </div>
  );
}

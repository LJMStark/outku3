import { useState } from 'react';
import { motion } from 'framer-motion';
import { Volume2, VolumeX, ChevronRight, Play, Heart, MapPin, Tag } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';

export default function KickstarterPage({ onNext }: PageProps) {
  const [soundEnabled, setSoundEnabled] = useState(true);

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
              i === 3 ? 'w-8 bg-white' : 'w-8 bg-white/30'
            }`}
          />
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-6">
        {/* Title */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="text-3xl font-bold text-white text-center mb-2"
        >
          Loved on every desk <span className="text-2xl">🖊️</span>
        </motion.h1>
        <motion.p
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-white/80 text-center mb-6"
        >
          Born on Kickstarter, alive on your phone...and IRL.
        </motion.p>

        {/* Kickstarter Card */}
        <motion.div
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="flex-1"
        >
          <div className="bg-white rounded-3xl overflow-hidden shadow-2xl">
            {/* Image */}
            <div className="relative">
              <img
                src="/kickstarter-card.jpg"
                alt="Inku Calendar Kickstarter"
                className="w-full h-48 object-cover"
              />
              {/* Play Button */}
              <div className="absolute inset-0 flex items-center justify-center">
                <motion.button
                  whileHover={{ scale: 1.1 }}
                  whileTap={{ scale: 0.9 }}
                  className="w-14 h-14 bg-black/70 rounded-full flex items-center justify-center"
                >
                  <Play className="w-6 h-6 text-white ml-1" fill="white" />
                </motion.button>
              </div>
              {/* Kickstarter Badge */}
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={{ delay: 0.5, type: 'spring' }}
                className="absolute top-2 right-2 bg-[#05CE78] text-white px-3 py-1 rounded-full text-xs font-bold flex items-center gap-1"
              >
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                </svg>
                funded with KICKSTARTER
              </motion.div>
              {/* Project We Love Badge */}
              <div className="absolute top-2 left-2">
                <div className="w-12 h-12 rounded-full bg-black/80 flex items-center justify-center border-2 border-white">
                  <Heart className="w-5 h-5 text-red-500" fill="red" />
                </div>
              </div>
            </div>

            {/* Card Content */}
            <div className="p-4">
              <h3 className="font-bold text-[#1A1A2E] text-lg mb-2">
                Inku Calendar: Watch your day flicker to life
              </h3>
              <div className="flex items-center gap-4 text-xs text-gray-500 mb-3">
                <span className="flex items-center gap-1">
                  <Heart className="w-3 h-3" /> Project We Love
                </span>
                <span className="flex items-center gap-1">
                  <MapPin className="w-3 h-3" /> San Francisco, CA
                </span>
                <span className="flex items-center gap-1">
                  <Tag className="w-3 h-3" /> Hardware
                </span>
              </div>
              <div className="flex justify-between items-end">
                <div>
                  <p className="text-2xl font-bold text-[#1A1A2E]">$284,684</p>
                  <p className="text-xs text-gray-500">pledged of $15,000 goal</p>
                </div>
                <div className="text-right">
                  <p className="text-xl font-bold text-[#1A1A2E]">1,508</p>
                  <p className="text-xs text-gray-500">backers</p>
                </div>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Character and Dialog */}
        <div className="flex items-end gap-3 mt-4">
          <motion.img
            src="/characters/inku-main.png"
            alt="Inku"
            className="w-16 h-16 object-contain"
            animate={{ y: [0, -4, 0] }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          />
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.4 }}
            className="flex-1 bg-[#F5F5F0] rounded-2xl p-3 shadow-lg relative"
          >
            <div className="absolute -left-2 bottom-4 w-0 h-0 border-t-6 border-t-transparent border-r-6 border-r-[#F5F5F0] border-b-6 border-b-transparent" />
            <p className="text-[#1A1A2E] text-xs leading-relaxed">
              Inku here! I'm so excited to bring <strong>focus, clarity and joy</strong> to your day!
            </p>
          </motion.div>
        </div>
      </div>

      {/* CTA Button */}
      <div className="px-6 pb-8">
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.6 }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onNext}
          className="w-full bg-[#1A1A2E] text-white py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2"
        >
          Get Started
          <ChevronRight className="w-5 h-5" />
        </motion.button>
      </div>
    </div>
  );
}

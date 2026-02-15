import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { Volume2, VolumeX, Calendar, CheckSquare, Clock, Mail, ListTodo, CalendarDays } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';

const floatingIcons = [
  { Icon: Calendar, color: '#4285F4', delay: 0 },
  { Icon: CheckSquare, color: '#EA4335', delay: 0.2 },
  { Icon: Clock, color: '#FBBC05', delay: 0.4 },
  { Icon: Mail, color: '#34A853', delay: 0.6 },
  { Icon: ListTodo, color: '#5B5FC7', delay: 0.8 },
  { Icon: CalendarDays, color: '#FF6B6B', delay: 1 },
];

export default function WelcomePage({ onNext }: PageProps) {
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [showDialog, setShowDialog] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setShowDialog(true), 500);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="h-full flex flex-col bg-[#0D8A6A] relative overflow-hidden">
      {/* Status Bar */}
      <div className="flex items-center justify-between px-6 pt-3 pb-2">
        <span className="text-white text-sm font-semibold">22:29</span>
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
        className="absolute top-14 left-4 w-10 h-10 rounded-full bg-white/20 flex items-center justify-center backdrop-blur-sm"
      >
        {soundEnabled ? (
          <Volume2 className="w-5 h-5 text-white" />
        ) : (
          <VolumeX className="w-5 h-5 text-white" />
        )}
      </button>

      {/* Floating Icons Container */}
      <div className="flex-1 relative flex items-center justify-center">
        {/* Rotating Icons Ring */}
        <motion.div
          className="absolute w-72 h-72"
          animate={{ rotate: 360 }}
          transition={{ duration: 20, repeat: Infinity, ease: 'linear' }}
        >
          {floatingIcons.map(({ Icon, color, delay }, index) => {
            const angle = (index * 60) * (Math.PI / 180);
            const x = Math.cos(angle) * 120;
            const y = Math.sin(angle) * 120;
            
            return (
              <motion.div
                key={index}
                className="absolute left-1/2 top-1/2"
                style={{
                  x: x - 20,
                  y: y - 20,
                }}
                animate={{ 
                  y: [y - 20, y - 30, y - 20],
                }}
                transition={{
                  duration: 2,
                  repeat: Infinity,
                  ease: 'easeInOut',
                  delay: delay,
                }}
              >
                <div 
                  className="w-10 h-10 rounded-xl flex items-center justify-center shadow-lg"
                  style={{ backgroundColor: color }}
                >
                  <Icon className="w-5 h-5 text-white" />
                </div>
              </motion.div>
            );
          })}
        </motion.div>

        {/* Center Emoji */}
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ duration: 0.5, type: 'spring' }}
          className="relative z-10"
        >
          <div className="text-8xl filter drop-shadow-lg">😌</div>
        </motion.div>
      </div>

      {/* Bottom Section with Character */}
      <div className="px-6 pb-8">
        {/* Character and Dialog */}
        <div className="flex items-end gap-3 mb-6">
          {/* Pixel Character */}
          <motion.div
            initial={{ x: -50, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            transition={{ delay: 0.3, duration: 0.5 }}
            className="flex-shrink-0"
          >
            <motion.img
              src="/characters/inku-main.png"
              alt="Inku"
              className="w-24 h-24 object-contain"
              animate={{ y: [0, -4, 0] }}
              transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
            />
          </motion.div>

          {/* Dialog Box */}
          {showDialog && (
            <motion.div
              initial={{ opacity: 0, scale: 0.9, x: 20 }}
              animate={{ opacity: 1, scale: 1, x: 0 }}
              transition={{ duration: 0.4 }}
              className="flex-1 bg-[#F5F5F0] rounded-2xl p-4 shadow-lg relative"
            >
              {/* Triangle pointer */}
              <div className="absolute -left-2 bottom-6 w-0 h-0 border-t-8 border-t-transparent border-r-8 border-r-[#F5F5F0] border-b-8 border-b-transparent" />
              <p className="text-[#1A1A2E] text-sm leading-relaxed">
                Inku here! I'm so excited to bring <strong>focus, clarity and joy</strong> to your day!
              </p>
            </motion.div>
          )}
        </div>

        {/* CTA Button */}
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.8, duration: 0.4 }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onNext}
          className="w-full bg-[#1A1A2E] text-white py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2"
        >
          I'm Ready! <span className="text-xl">❤️‍🔥</span>
        </motion.button>

        {/* Already have account link */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1 }}
          className="text-center mt-4 text-white/80 text-sm"
        >
          Already have an account?
        </motion.p>
      </div>
    </div>
  );
}

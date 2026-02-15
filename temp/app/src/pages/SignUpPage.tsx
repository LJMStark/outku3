import { useState } from 'react';
import { motion } from 'framer-motion';
import { ChevronLeft } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';

export default function SignUpPage({ onNext, onBack }: PageProps) {
  const [email, setEmail] = useState('');
  const [isValidEmail, setIsValidEmail] = useState(false);

  const handleEmailChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setEmail(value);
    setIsValidEmail(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value));
  };

  const handleGoogleSignIn = () => {
    // Simulate Google sign-in
    onNext();
  };

  const handleAppleSignIn = () => {
    // Simulate Apple sign-in
    onNext();
  };

  const handleMagicLink = () => {
    if (isValidEmail) {
      onNext();
    }
  };

  return (
    <div className="h-full flex flex-col bg-white relative overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-4 px-4 pt-3 pb-2">
        <button
          onClick={onBack}
          className="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center"
        >
          <ChevronLeft className="w-5 h-5 text-gray-600" />
        </button>
        <div className="flex-1">
          <p className="text-xs text-[#0D8A6A] font-medium">Personalization</p>
          {/* Progress Bar */}
          <div className="flex gap-1 mt-1">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className="h-1 flex-1 rounded-full bg-[#0D8A6A]"
              />
            ))}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-8">
        {/* Logo */}
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', duration: 0.5 }}
          className="flex justify-center mb-6"
        >
          <img
            src="/characters/inku-head.png"
            alt="Inku"
            className="w-24 h-24 object-contain"
          />
        </motion.div>

        {/* Title */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-2xl font-bold text-[#1A1A2E] text-center mb-2"
        >
          Sign up to Save Progress
        </motion.h1>
        <motion.p
          initial={{ y: -10, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="text-gray-500 text-center mb-8"
        >
          One more step to clarity, control and joy.
        </motion.p>

        {/* Social Sign In Buttons */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="space-y-3"
        >
          <button
            onClick={handleGoogleSignIn}
            className="w-full flex items-center justify-center gap-3 bg-[#1A1A2E] text-white py-4 rounded-full font-semibold shadow-lg hover:bg-[#2A2A3E] transition-colors"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24">
              <path
                fill="currentColor"
                d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
              />
              <path
                fill="currentColor"
                d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
              />
              <path
                fill="currentColor"
                d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
              />
              <path
                fill="currentColor"
                d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
              />
            </svg>
            Continue with Google
          </button>

          <button
            onClick={handleAppleSignIn}
            className="w-full flex items-center justify-center gap-3 bg-[#1A1A2E] text-white py-4 rounded-full font-semibold shadow-lg hover:bg-[#2A2A3E] transition-colors"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.22 7.13-.57 1.5-1.31 2.99-2.27 4.08zm-5.85-15.1c.07-2.04 1.76-3.79 3.78-3.94.29 2.32-1.93 4.48-3.78 3.94z"/>
            </svg>
            Continue with Apple
          </button>
        </motion.div>

        {/* Divider */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
          className="flex items-center gap-4 my-6"
        >
          <div className="flex-1 h-px bg-gray-200" />
          <span className="text-gray-400 text-sm">or</span>
          <div className="flex-1 h-px bg-gray-200" />
        </motion.div>

        {/* Email Input */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.5 }}
          className="space-y-3"
        >
          <input
            type="email"
            value={email}
            onChange={handleEmailChange}
            placeholder="Email address"
            className="w-full px-6 py-4 rounded-full border-2 border-gray-200 focus:border-[#0D8A6A] focus:outline-none transition-colors text-[#1A1A2E]"
          />
          <button
            onClick={handleMagicLink}
            disabled={!isValidEmail}
            className={`w-full py-4 rounded-full font-semibold shadow-lg transition-all ${
              isValidEmail
                ? 'bg-white text-[#1A1A2E] border-2 border-gray-200 hover:border-[#0D8A6A]'
                : 'bg-gray-100 text-gray-400 cursor-not-allowed'
            }`}
          >
            Send Magic Link
          </button>
        </motion.div>
      </div>
    </div>
  );
}

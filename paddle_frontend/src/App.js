import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import LandingPage from './pages/LandingPage';
import RegisterPage from './pages/RegisterPage';
import LoginPage from './pages/LoginPage';
import HomePage from "./pages/HomePage"

const App = () => {
  return (
    <Router>
      <Routes>
        <Route name="landing" path="/landing" element={<LandingPage />} />
        <Route anem="register" path="/register" element={<RegisterPage />} />
        <Route naem="login" path="/login" element={<LoginPage />} />
        <Route naem="home" path="/home" element={<HomePage />} />
        <Route path="*" element={<Navigate to="/landing" replace />} />
      </Routes>
    </Router>
  );
};

export default App;


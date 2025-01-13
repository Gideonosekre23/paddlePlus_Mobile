import React from "react";
import { Box, Typography, Button } from "@mui/material";
import "../styles//NavBar.css";
import { checkTokenValidity } from "../utils/api";

const NavBar = () => {
  const handleMBtn = async () => {
    const response = await checkTokenValidity();
  }
 
  return (
    <Box className="nav-bar">
      <Typography variant="h6" gutterBottom>
        Navigation
      </Typography>
      {/* Future options will go here */}
      <Button onClick={handleMBtn} variant="outlined" color="primary" size="large">
                  BTN
      </Button>
    </Box>
  );
};

export default NavBar;

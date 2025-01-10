import React, { useState } from 'react';
import { Box, Typography, IconButton, Button } from '@mui/material';
import PhotoCamera from '@mui/icons-material/PhotoCamera';

const FileUploadField = () => {
  const [fileName, setFileName] = useState('');

  const handlePhotoChange = (event) => {
    const file = event.target.files[0];
    if (file) {
      setFileName(file.name);
    }
  };

  return (
    <Box mt={2}>
      <Typography variant="body1" gutterBottom>
        Upload ID (Optional)
      </Typography>
      <input
        accept="image/*"
        id="file-input"
        type="file"
        style={{ display: 'none' }} // Hides the default input
        onChange={handlePhotoChange}
      />
      <label htmlFor="file-input">
        <Button variant="contained" component="span" color="primary">
          Choose File
        </Button>
      </label>
      {fileName && (
        <Typography variant="body2" mt={1}>
          Selected File: {fileName}
        </Typography>
      )}
    </Box>
  );
};

export default FileUploadField;

// import React from 'react';
// import { Box, IconButton, Typography } from '@mui/material';
// import PhotoCamera from '@mui/icons-material/PhotoCamera';

// const FileUploadField = () => {
//   const handlePhotoChange = (event) => {
//     console.log(event.target.files[0]);
//   };

//   return (
//     <Box mt={2}>
//       <Typography variant="body1" gutterBottom>
//         Upload Photo (Optional)
//       </Typography>
//       <input
//         accept="image/*"
//         id="icon-button-file"
//         type="file"
//         style={{ display: 'none' }}
//         onChange={handlePhotoChange}
//       />
//       <label htmlFor="icon-button-file">
//         <IconButton color="primary" aria-label="upload picture" component="span">
//           <PhotoCamera />
//         </IconButton>
//       </label>
//     </Box>
//   );
// };
